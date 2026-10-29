import Foundation

/// Offline match service. Matches live in memory on this device, and in demo mode simulated
/// friends join your lobby and play along, so lobbies, leaderboards and tournaments can be
/// tried without a server.
///
/// Bots advance lazily whenever a snapshot is read, staying at most one hole ahead of the
/// furthest human so the leaderboard stays interesting.
public actor InMemoryMatchService: MatchService {
    public nonisolated let isOnline = false

    private var matches: [UUID: Match] = [:]
    private var participants: [UUID: [Participant]] = [:]
    private var tournaments: [UUID: Tournament] = [:]
    private var entrants: [UUID: [TournamentEntrant]] = [:]

    private let simulateFriends: Bool
    private let botJoinDelays: [TimeInterval]
    private let secondsPerHole: TimeInterval
    private let layouts: @Sendable (String) -> CourseLayout?
    private let now: @Sendable () -> Date

    public init(
        simulateFriends: Bool = true,
        botJoinDelays: [TimeInterval] = [2.5, 5, 8],
        secondsPerHole: TimeInterval = 25,
        layouts: @escaping @Sendable (String) -> CourseLayout? = { DemoData.layout(forCourseID: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.simulateFriends = simulateFriends
        self.botJoinDelays = botJoinDelays
        self.secondsPerHole = secondsPerHole
        self.layouts = layouts
        self.now = now
    }

    // MARK: - Matches

    public func createMatch(_ match: Match, host: Participant) async throws -> MatchSnapshot {
        var match = match
        while matches.values.contains(where: { $0.code == match.code && $0.status != .finished }) {
            match.code = JoinCode.generate()
        }
        matches[match.id] = match
        participants[match.id] = [host]
        return try await snapshot(matchID: match.id)
    }

    public func joinMatch(code: String, as participant: Participant) async throws -> MatchSnapshot {
        let normalized = JoinCode.normalize(code)
        guard let match = matches.values.first(where: { $0.code == normalized && $0.status != .finished }) else {
            if matches.values.contains(where: { $0.code == normalized }) { throw MatchServiceError.alreadyFinished }
            throw MatchServiceError.codeNotFound(normalized)
        }
        try await upsertParticipant(participant, matchID: match.id)
        return try await snapshot(matchID: match.id)
    }

    public func snapshot(matchID: UUID) async throws -> MatchSnapshot {
        guard matches[matchID] != nil else { throw MatchServiceError.notFound }
        if simulateFriends { advanceBots(matchID: matchID) }
        return MatchSnapshot(match: matches[matchID]!, participants: participants[matchID] ?? [])
    }

    public func updateMatch(_ match: Match) async throws {
        guard matches[match.id] != nil else { throw MatchServiceError.notFound }
        matches[match.id] = match
    }

    public func upsertParticipant(_ participant: Participant, matchID: UUID) async throws {
        guard matches[matchID] != nil else { throw MatchServiceError.notFound }
        var list = participants[matchID] ?? []
        if let index = list.firstIndex(where: { $0.id == participant.id }) {
            list[index] = participant
        } else {
            list.append(participant)
        }
        participants[matchID] = list
    }

    public func removeParticipant(_ participantID: UUID, matchID: UUID) async throws {
        participants[matchID]?.removeAll { $0.id == participantID }
    }

    // MARK: - Tournaments

    public func createTournament(_ tournament: Tournament, host: TournamentEntrant) async throws -> TournamentSnapshot {
        var tournament = tournament
        while tournaments.values.contains(where: { $0.code == tournament.code && $0.status != .finished }) {
            tournament.code = JoinCode.generate()
        }
        tournaments[tournament.id] = tournament
        var list = [host]
        if simulateFriends {
            list += DemoData.friends.prefix(3).map {
                TournamentEntrant(id: $0.id, name: $0.name, avatar: $0.avatar, handicapIndex: $0.handicapIndex)
            }
        }
        entrants[tournament.id] = list
        return try await tournamentSnapshot(id: tournament.id)
    }

    public func joinTournament(code: String, as entrant: TournamentEntrant) async throws -> TournamentSnapshot {
        let normalized = JoinCode.normalize(code)
        guard let tournament = tournaments.values.first(where: { $0.code == normalized && $0.status != .finished }) else {
            throw MatchServiceError.codeNotFound(normalized)
        }
        if !(entrants[tournament.id] ?? []).contains(where: { $0.id == entrant.id }) {
            entrants[tournament.id, default: []].append(entrant)
        }
        return try await tournamentSnapshot(id: tournament.id)
    }

    public func tournamentSnapshot(id: UUID) async throws -> TournamentSnapshot {
        guard let tournament = tournaments[id] else { throw MatchServiceError.notFound }
        var rounds: [Int: MatchSnapshot] = [:]
        for round in tournament.rounds {
            if let matchID = round.matchID, let snap = try? await snapshot(matchID: matchID) {
                rounds[round.number] = snap
            }
        }
        return TournamentSnapshot(tournament: tournament, entrants: entrants[id] ?? [], rounds: rounds)
    }

    public func updateTournament(_ tournament: Tournament) async throws {
        guard tournaments[tournament.id] != nil else { throw MatchServiceError.notFound }
        tournaments[tournament.id] = tournament
    }

    // MARK: - Simulated friends

    private func advanceBots(matchID: UUID) {
        guard let match = matches[matchID] else { return }
        var list = participants[matchID] ?? []
        let time = now()

        // Lobby: friends trickle in after a few seconds (tournament rounds bring their entrants).
        if match.status == .lobby || match.status == .live {
            let roster: [Participant]
            if let tid = match.tournamentID, let tournamentEntrants = entrants[tid] {
                roster = tournamentEntrants
                    .filter { entrant in DemoData.friends.contains { $0.id == entrant.id } }
                    .compactMap { entrant in DemoData.friends.first { $0.id == entrant.id } }
            } else {
                roster = Array(DemoData.friends.prefix(botJoinDelays.count))
            }
            for (i, bot) in roster.enumerated() where !list.contains(where: { $0.id == bot.id }) {
                let delay = i < botJoinDelays.count ? botJoinDelays[i] : botJoinDelays.last ?? 0
                if match.tournamentID != nil || time.timeIntervalSince(match.createdAt) >= delay {
                    var joined = bot
                    joined.updatedAt = time
                    list.append(joined)
                }
            }
        }

        // Live: bots finish holes on a timer, never more than one ahead of the humans.
        if match.status == .live, let started = match.startedAt {
            let humanProgress = list.filter { !$0.isBot }.map { p in
                match.holeNumbers.filter { p.score(for: $0) != nil }.count
            }.max() ?? 0
            let layout = layouts(match.course.id)
            for i in list.indices where list[i].isBot {
                var handicap = list[i].handicapIndex
                if match.isOneBallTeamGame, let team = match.team(of: list[i].id) {
                    let members = list.filter { team.memberIDs.contains($0.id) }
                    // One ball per team: a bot only keeps the card for an all-bot team, and only
                    // its first member does. Everyone else just walks along with their team.
                    if members.contains(where: { !$0.isBot }) || members.first(where: \.isBot)?.id != list[i].id {
                        let progress = match.holeNumbers.filter { hole in members.contains { $0.score(for: hole) != nil } }.count
                        let next = progress < match.holeNumbers.count ? match.holeNumbers[progress] : nil
                        list[i].currentHole = next
                        list[i].isFinished = next == nil
                        continue
                    }
                    // The team ball plays better than any one of its players.
                    let indexes = members.map { $0.handicapIndex ?? 18 }
                    handicap = match.teamFormat == .scramble
                        ? max(0, (indexes.min() ?? 18) - 4)
                        : indexes.reduce(0, +) / Double(max(1, indexes.count))
                }
                let byTime = Int(time.timeIntervalSince(started) / secondsPerHole * jitter(list[i].id))
                let target = min(match.holeNumbers.count, min(byTime, humanProgress + 1))
                var completed = match.holeNumbers.filter { list[i].score(for: $0) != nil }.count
                while completed < target {
                    let number = match.holeNumbers[completed]
                    if let hole = match.course.hole(number) {
                        let score = BotGolfer.holeScore(
                            playerID: list[i].id, handicap: handicap, hole: hole,
                            gameType: match.course.gameType, layout: layout?.hole(number),
                            salt: stableSalt(match.id),
                            startTime: started.addingTimeInterval(Double(completed) * secondsPerHole)
                        )
                        list[i].setScore(score)
                        list[i].lastLocation = score.holeLocation ?? list[i].lastLocation
                    }
                    completed += 1
                }
                let next = completed < match.holeNumbers.count ? match.holeNumbers[completed] : nil
                list[i].currentHole = next
                list[i].isFinished = next == nil
                if let next, let tee = layout?.hole(next)?.teePoint { list[i].lastLocation = tee }
                list[i].updatedAt = time
            }
        }
        participants[matchID] = list
    }

    private func stableSalt(_ id: UUID) -> Int {
        var rng = SplitMix64(id, salt: 1)
        return Int(rng.next() & 0xFFFF)
    }

    /// Each bot plays at a slightly different pace.
    private func jitter(_ id: UUID) -> Double {
        var rng = SplitMix64(id)
        return Double.random(in: 0.85...1.15, using: &rng)
    }
}
