import Foundation
import Observation
import GolfKit

/// A live match on this device: polls for everyone's scores, uploads the cards this device
/// keeps (yours and any guests), and computes the leaderboard.
@Observable
@MainActor
final class MatchSession: Identifiable {
    let id: UUID
    let myID: UUID
    private(set) var snapshot: MatchSnapshot
    private(set) var lastError: String?
    private(set) var lastSynced = Date()
    private(set) var isPolling = false

    @ObservationIgnored let service: any MatchService
    @ObservationIgnored var onFinished: ((MatchSnapshot) -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var uploads: [UUID: Task<Void, Never>] = [:]
    /// Team changes the server may not have seen yet.
    @ObservationIgnored private var matchEditsInFlight = 0

    init(service: any MatchService, snapshot: MatchSnapshot, myID: UUID) {
        self.id = snapshot.match.id
        self.service = service
        self.snapshot = snapshot
        self.myID = myID
    }

    var match: Match { snapshot.match }
    var isHost: Bool { match.hostID == myID }
    var me: Participant? { snapshot.participant(myID) }
    var leaderboard: [LeaderboardEntry] { Leaderboard.entries(for: snapshot) }

    /// Cards this device scores: yours first, then guests.
    var scoredHere: [Participant] {
        let mine = snapshot.participants.filter { $0.id == myID }
        let guests = snapshot.participants.filter { $0.id != myID && $0.scoredBy == myID }
        return mine + guests
    }

    var myPosition: LeaderboardEntry? { leaderboard.first { $0.id == myID } }

    // MARK: - Teams

    var teamLeaderboard: [TeamLeaderboardEntry] { TeamLeaderboard.entries(for: snapshot) }
    var myTeam: Team? { match.team(of: myID) }
    var myTeamPosition: TeamLeaderboardEntry? {
        guard let myTeam else { return nil }
        return teamLeaderboard.first { $0.id == myTeam.id }
    }

    /// Players who joined but aren't on a team yet.
    var unplacedPlayers: [Participant] {
        guard match.isTeamGame else { return [] }
        return snapshot.participants.filter { match.team(of: $0.id) == nil }
    }

    /// Host: moves a player onto another team.
    func move(_ playerID: UUID, toTeam teamID: UUID) async {
        await editTeams { TeamBuilder.moving(playerID, to: teamID, in: $0) }
    }

    /// Host: shares everyone out into sides of even strength.
    func balanceTeams() async {
        let players = snapshot.participants
        await editTeams { TeamBuilder.balanced(players, into: $0) }
    }

    /// Host: puts newcomers on the smallest team as they join.
    func placeNewPlayers() async {
        guard !unplacedPlayers.isEmpty else { return }
        let players = snapshot.participants
        await editTeams { TeamBuilder.placingNewPlayers(players, in: $0) }
    }

    private func editTeams(_ change: ([Team]) -> [Team]) async {
        guard isHost, match.isTeamGame else { return }
        var updated = match
        updated.teams = change(updated.teams)
        guard updated.teams != match.teams else { return }
        snapshot.match = updated
        matchEditsInFlight += 1
        defer { matchEditsInFlight -= 1 }
        do {
            try await service.updateMatch(updated)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sync

    func startPolling(every seconds: Double = 4) {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    func refresh() async {
        do {
            let remote = try await service.snapshot(matchID: id)
            merge(remote)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func merge(_ remote: MatchSnapshot) {
        var merged = remote
        // Keep local edits that the server hasn't seen yet.
        for local in scoredHere {
            if let i = merged.participants.firstIndex(where: { $0.id == local.id }) {
                if local.updatedAt > merged.participants[i].updatedAt { merged.participants[i] = local }
            } else if uploads[local.id] != nil {
                merged.participants.append(local)
            }
        }
        // Keep the host's team changes until the server has them.
        if matchEditsInFlight > 0 { merged.match = snapshot.match }
        let wasFinished = snapshot.match.status == .finished
        snapshot = merged
        lastSynced = Date()
        if !wasFinished && merged.match.status == .finished {
            stopPolling()
            onFinished?(merged)
        }
    }

    /// Updates a card this device owns, immediately locally and shortly after on the server.
    func update(_ participant: Participant) {
        var p = participant
        p.updatedAt = Date()
        if let i = snapshot.participants.firstIndex(where: { $0.id == p.id }) {
            snapshot.participants[i] = p
        } else {
            snapshot.participants.append(p)
        }
        upload(p)
    }

    private func upload(_ participant: Participant) {
        uploads[participant.id]?.cancel()
        let service = self.service
        let matchID = id
        uploads[participant.id] = Task { [weak self] in
            // Debounce quick +/- taps into one request.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                try await service.upsertParticipant(participant, matchID: matchID)
                self?.uploads[participant.id] = nil
                self?.lastError = nil
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    func setScore(_ score: HoleScore, for participantID: UUID) {
        guard var p = snapshot.participant(participantID) else { return }
        p.setScore(score)
        if participantID == myID || p.scoredBy == myID {
            update(p)
        }
    }

    func setCurrentHole(_ hole: Int?, location: GeoPoint?, for participantID: UUID) {
        guard var p = snapshot.participant(participantID) else { return }
        guard p.currentHole != hole || location != nil else { return }
        p.currentHole = hole
        if let location { p.lastLocation = location }
        update(p)
    }

    // MARK: - Lobby

    func addGuest(name: String) {
        var guest = Participant(id: UUID(), name: name, avatar: .random())
        guest.scoredBy = myID
        guest.currentHole = match.status == .live ? match.holeNumbers.first : nil
        update(guest)
    }

    func removeGuest(_ id: UUID) async {
        snapshot.participants.removeAll { $0.id == id }
        try? await service.removeParticipant(id, matchID: self.id)
    }

    func start() async throws {
        var m = match
        m.status = .live
        m.startedAt = Date()
        if m.isTeamGame {
            // Everyone who's here plays: place latecomers and drop anyone who left.
            let present = Set(snapshot.participants.map(\.id))
            m.teams = TeamBuilder.placingNewPlayers(snapshot.participants, in: m.teams).map { team in
                var kept = team
                kept.memberIDs = team.memberIDs.filter(present.contains)
                return kept
            }
        }
        try await service.updateMatch(m)
        snapshot.match = m
        for p in scoredHere {
            var started = p
            started.currentHole = m.holeNumbers.first
            update(started)
        }
    }

    func finish() async throws {
        // Flush any pending card uploads first.
        for p in scoredHere {
            var done = p
            done.isFinished = true
            done.currentHole = nil
            snapshot.participants = snapshot.participants.map { $0.id == done.id ? done : $0 }
            try? await service.upsertParticipant(done, matchID: id)
        }
        if isHost {
            var m = match
            m.status = .finished
            m.finishedAt = Date()
            try await service.updateMatch(m)
            snapshot.match = m
        }
        stopPolling()
        onFinished?(snapshot)
    }

    var shareMessage: String {
        "Join my round at \(match.course.name) on Fairway ⛳️ Code: \(match.code)"
    }
}

/// A tournament on this device: standings, round management for the host and polling.
@Observable
@MainActor
final class TournamentSession: Identifiable {
    let id: UUID
    let myID: UUID
    private(set) var snapshot: TournamentSnapshot
    private(set) var lastError: String?

    @ObservationIgnored let service: any MatchService
    @ObservationIgnored var onUpdate: ((TournamentSnapshot) -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(service: any MatchService, snapshot: TournamentSnapshot, myID: UUID) {
        self.id = snapshot.tournament.id
        self.service = service
        self.snapshot = snapshot
        self.myID = myID
    }

    var tournament: Tournament { snapshot.tournament }
    var isHost: Bool { tournament.hostID == myID }
    var standings: [TournamentStanding] { TournamentStandings.compute(snapshot) }
    var liveRound: TournamentRound? { tournament.rounds.first { $0.status == .live } }
    var nextRound: TournamentRound? { tournament.rounds.first { $0.status == nil || $0.status == .lobby } }

    func startPolling(every seconds: Double = 6) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        do {
            snapshot = try await service.tournamentSnapshot(id: id)
            lastError = nil
            onUpdate?(snapshot)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Host: creates the match for a round and opens it straight into play.
    func startRound(_ number: Int, host: Participant) async throws -> MatchSnapshot {
        guard let index = tournament.rounds.firstIndex(where: { $0.number == number }),
              let course = tournament.rounds[index].course else { throw MatchServiceError.notFound }
        let round = tournament.rounds[index]
        let match = Match(
            code: JoinCode.generate(), hostID: myID, name: "\(tournament.name) · Round \(number)",
            course: course, tee: round.tee, holeNumbers: round.holeNumbers,
            format: tournament.format == .stableford ? .stableford : .strokePlay,
            useHandicaps: tournament.useHandicaps, status: .live, startedAt: Date(),
            tournamentID: tournament.id, roundNumber: number
        )
        var host = host
        host.currentHole = match.holeNumbers.first
        let created = try await service.createMatch(match, host: host)

        var updated = tournament
        updated.rounds[index].matchID = created.match.id
        updated.rounds[index].matchCode = created.match.code
        updated.rounds[index].status = .live
        updated.status = .inProgress
        try await service.updateTournament(updated)
        snapshot.tournament = updated
        snapshot.rounds[number] = created
        onUpdate?(snapshot)
        return created
    }

    /// Host: closes a round; the tournament finishes after the last one.
    func finishRound(_ number: Int) async throws {
        guard let index = tournament.rounds.firstIndex(where: { $0.number == number }) else { return }
        var updated = tournament
        if let matchSnapshot = snapshot.rounds[number] {
            var match = matchSnapshot.match
            match.status = .finished
            match.finishedAt = Date()
            try await service.updateMatch(match)
            snapshot.rounds[number]?.match = match
        }
        updated.rounds[index].status = .finished
        if updated.rounds.allSatisfy({ $0.status == .finished }) {
            updated.status = .finished
        }
        try await service.updateTournament(updated)
        snapshot.tournament = updated
        onUpdate?(snapshot)
    }

    var shareMessage: String {
        "Join \(tournament.name) on Fairway 🏆 Code: \(tournament.code)"
    }
}
