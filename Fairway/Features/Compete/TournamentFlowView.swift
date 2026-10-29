import SwiftUI
import Charts
import GolfKit

/// Tournament dashboard: standings across rounds, each player's current hole, host
/// controls for starting and closing rounds, and a way into the live round.
struct TournamentFlowView: View {
    @Environment(AppModel.self) private var app
    let tournamentID: UUID

    @State private var session: TournamentSession?
    @State private var archived: TournamentSnapshot?
    @State private var loadError: String?
    @State private var playingMatch: MatchID?
    @State private var busy = false
    @State private var selectedEntrant: TournamentStanding?
    @State private var showMap = false

    struct MatchID: Identifiable { let id: UUID }

    private var snapshot: TournamentSnapshot? { session?.snapshot ?? archived }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    dashboard(snapshot)
                } else if let loadError {
                    EmptyStateView(title: "Couldn't load tournament", message: loadError, systemImage: "wifi.exclamationmark")
                } else {
                    ProgressView("Loading…").controlSize(.large)
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { app.presentation = nil } label: { Image(systemName: "chevron.down") }
                }
                if let session {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: session.shareMessage) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .task { await connect() }
            .onDisappear { session?.stopPolling() }
            .fullScreenCover(item: $playingMatch) { match in
                MatchFlowView(matchID: match.id)
                    .environment(app)
                    .onDisappear { Task { await session?.refresh() } }
            }
            .sheet(item: $selectedEntrant) { standing in
                if let snapshot {
                    TournamentPlayerView(snapshot: snapshot, entrantID: standing.entrant.id)
                }
            }
            .navigationDestination(isPresented: $showMap) {
                if let round = session?.liveRound, let course = round.course, let snap = snapshot?.rounds[round.number] {
                    CourseMapView(course: course, players: snap.participants)
                }
            }
        }
    }

    // MARK: - Dashboard

    private func dashboard(_ snapshot: TournamentSnapshot) -> some View {
        let standings = TournamentStandings.compute(snapshot)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header(snapshot).reveal(0)
                VStack(alignment: .leading, spacing: 18) {
                    roundsList(snapshot)
                    controls(snapshot)
                }
                .reveal(1)
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Leaderboard", subtitle: snapshot.tournament.useHandicaps ? "Net \(snapshot.tournament.format.displayName.lowercased())" : snapshot.tournament.format.displayName) {
                        if snapshot.tournament.status == .inProgress { LiveBadge() }
                    }
                    StandingsTable(standings: standings, tournament: snapshot.tournament, myID: app.profile.id) { selectedEntrant = $0 }
                }
                .reveal(2)
                if let leader = standings.first, leader.holesPlayed > 0 {
                    LeaderSummary(standing: leader)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
            .animation(.snappySpring, value: standings.map(\.id))
        }
        .refreshable { await session?.refresh() }
    }

    private func header(_ snapshot: TournamentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Tournament · \(snapshot.tournament.gameType.displayName) · \(snapshot.entrants.count) players")
                Text(snapshot.tournament.name).font(.display(32)).lineLimit(2)
            }
            if snapshot.tournament.status != .finished {
                HStack(alignment: .center, spacing: 16) {
                    CodeTiles(code: snapshot.tournament.code, tileSize: 40)
                    Text("Share this code so friends can enter.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func roundsList(_ snapshot: TournamentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Rounds")
            DividedList(snapshot.tournament.rounds) { round in
                HStack(spacing: 14) {
                    Text("R\(round.number)")
                        .font(.figure(15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                    Text(round.course?.name ?? "Course to be confirmed").font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                    switch round.status {
                    case .live: LiveBadge()
                    case .finished: Eyebrow("Complete", color: Theme.fairway)
                    default: Eyebrow("Upcoming")
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func controls(_ snapshot: TournamentSnapshot) -> some View {
        if let session, snapshot.tournament.status != .finished {
            VStack(spacing: 10) {
                if let live = session.liveRound {
                    Button {
                        Task { await play(live) }
                    } label: {
                        Label("Play round \(live.number)", systemImage: "figure.golf")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)

                    HStack(spacing: 10) {
                        Button { showMap = true } label: {
                            Label("Live map", systemImage: "map")
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        if session.isHost {
                            Button {
                                Task { await finishRound(live.number) }
                            } label: {
                                Text(live.number == snapshot.tournament.rounds.count ? "Finish event" : "Close round \(live.number)")
                            }
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.flag))
                            .disabled(busy)
                        }
                    }
                } else if let next = session.nextRound {
                    if session.isHost {
                        Button {
                            Task { await startRound(next.number) }
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(Theme.onAccent) }
                                Label("Start round \(next.number)", systemImage: "play.fill")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy)
                    } else {
                        Label("Waiting for the host to start round \(next.number)", systemImage: "hourglass")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !app.isOnline {
                    Text("Demo mode: simulated friends play each round alongside you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Actions

    private func connect() async {
        if session != nil || archived != nil { return }
        if let existing = app.tournamentSessions[tournamentID] {
            session = existing
        } else if let game = app.library.activeGames.first(where: { $0.id == tournamentID }) {
            do {
                session = try await app.tournamentSession(for: game)
            } catch {
                archived = app.library.tournaments.first { $0.tournament.id == tournamentID }
                if archived == nil { loadError = error.localizedDescription }
            }
        } else {
            archived = app.library.tournaments.first { $0.tournament.id == tournamentID }
            if archived == nil { loadError = "This tournament isn't on this device any more." }
        }
        session?.startPolling()
    }

    private func startRound(_ number: Int) async {
        guard let session else { return }
        busy = true
        defer { busy = false }
        do {
            let type = session.tournament.gameType
            let created = try await session.startRound(number, host: app.meAsParticipant(for: type))
            let matchSession = MatchSession(service: app.matchService, snapshot: created, myID: app.profile.id)
            app.adopt(matchSession)
            playingMatch = MatchID(id: created.match.id)
        } catch {
            app.showError(error)
        }
    }

    private func play(_ round: TournamentRound) async {
        busy = true
        defer { busy = false }
        do {
            let match = try await app.joinTournamentRound(round)
            playingMatch = MatchID(id: match.id)
        } catch {
            app.showError(error)
        }
    }

    private func finishRound(_ number: Int) async {
        guard let session else { return }
        busy = true
        defer { busy = false }
        do {
            try await session.finishRound(number)
            if session.tournament.status == .finished {
                app.show(Banner(title: "Tournament complete", message: TournamentStandings.compute(session.snapshot).first.map { "\($0.entrant.name) wins!" }, style: .celebration))
            }
        } catch {
            app.showError(error)
        }
    }
}

// MARK: - Standings

struct StandingsTable: View {
    let standings: [TournamentStanding]
    let tournament: Tournament
    let myID: UUID
    let onSelect: (TournamentStanding) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("POS").frame(width: 38, alignment: .leading)
                Text("PLAYER")
                Spacer()
                Text("TODAY").frame(width: 52, alignment: .trailing)
                Text("THRU").frame(width: 44, alignment: .trailing)
                Text(tournament.format == .stableford ? "PTS" : "TOTAL").frame(width: 58, alignment: .trailing)
            }
            .font(.eyebrow)
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            Hairline()

            ForEach(standings) { standing in
                Button { onSelect(standing) } label: {
                    HStack(spacing: 0) {
                        Text(standing.positionLabel)
                            .font(.figure(15, weight: .semibold))
                            .foregroundStyle(standing.position == 1 && standing.holesPlayed > 0 ? Theme.gold : .primary)
                            .frame(width: 38, alignment: .leading)
                        AvatarView(avatar: standing.entrant.avatar, size: 28, showsRing: standing.id == myID)
                            .padding(.trailing, 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(standing.entrant.name).font(.body.weight(standing.id == myID ? .semibold : .medium)).lineLimit(1)
                            if standing.isPlaying, let hole = standing.currentHole {
                                Text("On hole \(hole)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.fairway)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(standing.today.map(Leaderboard.formatToPar) ?? "–")
                            .font(.figure(15))
                            .foregroundStyle((standing.today ?? 0) < 0 ? Theme.flag : .primary)
                            .frame(width: 52, alignment: .trailing)
                        Text(thruText(standing))
                            .font(.figure(14))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Text(standing.statusText)
                            .font(.figure(17, weight: .semibold))
                            .contentTransition(.numericText())
                            .frame(width: 58, alignment: .trailing)
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                Hairline()
            }
        }
    }

    private func thruText(_ standing: TournamentStanding) -> String {
        guard let thru = standing.thru else { return "–" }
        if !standing.isPlaying && thru > 0 { return "F" }
        return "\(thru)"
    }
}

/// The current leader and how they got there.
struct LeaderSummary: View {
    let standing: TournamentStanding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Leader")
            HStack(spacing: 14) {
                AvatarView(avatar: standing.entrant.avatar, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(standing.entrant.name).font(.display(22))
                    Text(standing.statusText).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "crown")
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
            }
            MetricGrid(items: [
                MetricItem(label: "Birdies+", value: "\(standing.stats.birdiesOrBetter)"),
                MetricItem(label: "GIR", value: standing.stats.greensInRegulation.percentText),
                MetricItem(label: "Putts/hole", value: standing.stats.puttsPerHole.map { String(format: "%.1f", $0) } ?? "—"),
            ], columns: 3, compact: true)
            .overlay(alignment: .top) { Hairline() }
        }
    }
}

// MARK: - Player detail

/// Deep stats for one tournament player: position, current hole, per-round cards, charts.
struct TournamentPlayerView: View {
    @Environment(AppModel.self) private var app
    let snapshot: TournamentSnapshot
    let entrantID: UUID

    var body: some View {
        NavigationStack {
            ScrollView {
                if let standing = TournamentStandings.compute(snapshot).first(where: { $0.id == entrantID }) {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        header(standing)
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Scoring")
                            MetricGrid(items: statItems(standing), columns: 3)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Average by par")
                            MetricGrid(items: [3, 4, 5].map { par in
                                MetricItem(label: "Par \(par)", value: standing.stats.averageStrokes(onPar: par).map { String(format: "%.2f", $0) } ?? "—")
                            }, columns: 3)
                        }
                        ForEach(snapshot.tournament.rounds) { round in
                            if let pair = TournamentStandings.scorecard(for: entrantID, round: round.number, in: snapshot) {
                                let match = pair.0
                                let card = pair.1
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Round \(round.number)", subtitle: match.course.name)
                                    HoleByHoleChart(match: match, participant: card)
                                    ScorecardGrid(course: match.course, holes: match.holeNumbers, tee: match.tee,
                                                  players: [ScorecardPlayerRow(participant: card)], showsLengths: false, units: app.units)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 12)
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }

    private func header(_ standing: TournamentStanding) -> some View {
        HStack(alignment: .center, spacing: 16) {
            AvatarView(avatar: standing.entrant.avatar, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(standing.entrant.name).font(.display(26))
                Text(headerDetail(standing)).font(.subheadline).foregroundStyle(.secondary)
                if standing.isPlaying, let hole = standing.currentHole {
                    Label("Playing hole \(hole) · thru \(standing.thru ?? 0)", systemImage: "figure.golf")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.fairway)
                }
            }
            Spacer()
            Text(standing.statusText).font(.display(34, weight: .regular))
        }
    }

    private func headerDetail(_ standing: TournamentStanding) -> String {
        var parts = ["Position \(standing.positionLabel)"]
        if let index = standing.entrant.handicapIndex { parts.append("Handicap \(HandicapCalculator.format(index))") }
        return parts.joined(separator: " · ")
    }

    private func statItems(_ standing: TournamentStanding) -> [MetricItem] {
        let s = standing.stats
        return [
            MetricItem(label: "Holes", value: "\(s.holesPlayed)"),
            MetricItem(label: "Birdies+", value: "\(s.birdiesOrBetter)", tint: s.birdiesOrBetter > 0 ? Theme.flag : nil),
            MetricItem(label: "Bogey+", value: "\(s.count(.bogey) + s.count(.doubleBogey) + s.count(.tripleOrWorse))"),
            MetricItem(label: "GIR", value: s.greensInRegulation.percentText),
            MetricItem(label: "Fairways", value: s.fairways.percentText),
            MetricItem(label: "Putts/hole", value: s.puttsPerHole.map { String(format: "%.2f", $0) } ?? "—"),
        ]
    }
}

/// Running score to par through a round.
struct HoleByHoleChart: View {
    let match: Match
    let participant: Participant

    struct Point: Identifiable {
        let hole: Int
        let index: Int
        let cumulative: Int
        let diff: Int
        var id: Int { index }
    }

    var body: some View {
        let points = makePoints()
        if points.count > 1 {
            Chart(points) { point in
                RuleMark(y: .value("Par", 0))
                    .foregroundStyle(Theme.hairline)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                LineMark(x: .value("Hole", point.index), y: .value("To par", point.cumulative))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Hole", point.index), y: .value("To par", point.cumulative))
                    .foregroundStyle(point.diff < 0 ? Theme.flag : (point.diff == 0 ? Color.primary : Theme.water))
                    .symbolSize(point.diff == 0 ? 14 : 40)
            }
            .chartYScale(domain: .automatic(includesZero: true, reversed: true))
            .chartXAxis {
                AxisMarks(values: points.map(\.index)) { value in
                    AxisValueLabel {
                        if let i = value.as(Int.self), i - 1 < points.count, i >= 1 { Text("\(points[i - 1].hole)") }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    private func makePoints() -> [Point] {
        var total = 0
        var result: [Point] = []
        for (i, hole) in match.holeNumbers.enumerated() {
            guard let score = participant.score(for: hole), let par = match.course.hole(hole)?.par else { continue }
            total += score.strokes - par
            result.append(Point(hole: hole, index: i + 1, cumulative: total, diff: score.strokes - par))
        }
        return result
    }
}
