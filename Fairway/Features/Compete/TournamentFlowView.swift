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
            VStack(alignment: .leading, spacing: 18) {
                header(snapshot)
                roundsStrip(snapshot)
                controls(snapshot)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionHeader(title: "Leaderboard", subtitle: snapshot.tournament.useHandicaps ? "Net \(snapshot.tournament.format.displayName.lowercased())" : snapshot.tournament.format.displayName)
                        if snapshot.tournament.status == .inProgress { LiveBadge() }
                    }
                    StandingsTable(standings: standings, tournament: snapshot.tournament, myID: app.profile.id) { selectedEntrant = $0 }
                }
                if let leader = standings.first, leader.holesPlayed > 0 {
                    LeaderCard(standing: leader)
                }
            }
            .padding()
            .animation(.snappySpring, value: standings.map(\.id))
        }
        .refreshable { await session?.refresh() }
    }

    private func header(_ snapshot: TournamentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "trophy.fill").font(.title2)
                Text(snapshot.tournament.name).font(.rounded(26, weight: .heavy)).lineLimit(2)
            }
            HStack(spacing: 8) {
                InfoPill(text: snapshot.tournament.gameType.displayName, systemImage: snapshot.tournament.gameType.symbolName, tint: .white)
                InfoPill(text: "\(snapshot.entrants.count) players", systemImage: "person.2.fill", tint: .white)
            }
            if snapshot.tournament.status != .finished {
                HStack(spacing: 12) {
                    CodeTiles(code: snapshot.tournament.code, tileSize: 40)
                    Text("Share this code\nso friends can enter")
                        .font(.caption.weight(.semibold))
                        .opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func roundsStrip(_ snapshot: TournamentSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(snapshot.tournament.rounds) { round in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Round \(round.number)").font(.subheadline.weight(.bold))
                        Text(round.course?.name ?? "TBC").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Group {
                            switch round.status {
                            case .live: LiveBadge()
                            case .finished: InfoPill(text: "Complete", systemImage: "checkmark", tint: Theme.fairway)
                            default: InfoPill(text: "Upcoming", tint: .secondary)
                            }
                        }
                    }
                    .frame(width: 150, alignment: .leading)
                    .cardStyle(padding: 12)
                }
            }
            .padding(2)
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

                    Button { showMap = true } label: {
                        Label("Where is everyone?", systemImage: "map.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.water))

                    if session.isHost {
                        Button {
                            Task { await finishRound(live.number) }
                        } label: {
                            Label(live.number == snapshot.tournament.rounds.count ? "Finish tournament" : "Close round \(live.number)", systemImage: "flag.checkered")
                        }
                        .buttonStyle(SecondaryButtonStyle(tint: Theme.flag))
                        .disabled(busy)
                    }
                } else if let next = session.nextRound {
                    if session.isHost {
                        Button {
                            Task { await startRound(next.number) }
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Label("Start round \(next.number)", systemImage: "play.fill")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(gradient: Theme.goldGradient))
                        .disabled(busy)
                    } else {
                        Label("Waiting for the host to start round \(next.number)", systemImage: "hourglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .cardStyle()
                    }
                }
                if !app.isOnline {
                    Text("Demo mode: simulated friends play each round alongside you.")
                        .font(.caption).foregroundStyle(.secondary)
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
            HStack {
                Text("POS").frame(width: 36, alignment: .leading)
                Text("PLAYER")
                Spacer()
                Text("TODAY").frame(width: 56)
                Text("THRU").frame(width: 46)
                Text(tournament.format == .stableford ? "PTS" : "TOTAL").frame(width: 56, alignment: .trailing)
            }
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ForEach(standings) { standing in
                Button { onSelect(standing) } label: {
                    HStack {
                        Text(standing.positionLabel)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(standing.position == 1 && standing.holesPlayed > 0 ? Theme.gold : .primary)
                            .frame(width: 36, alignment: .leading)
                        AvatarView(avatar: standing.entrant.avatar, size: 30, showsRing: standing.id == myID)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(standing.entrant.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if standing.isPlaying, let hole = standing.currentHole {
                                Label("On hole \(hole)", systemImage: "flag.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.fairway)
                            }
                        }
                        Spacer()
                        Text(standing.today.map(Leaderboard.formatToPar) ?? "–")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle((standing.today ?? 0) < 0 ? Theme.flag : .primary)
                            .frame(width: 56)
                        Text(thruText(standing))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 46)
                        Text(standing.statusText)
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                            .frame(width: 56, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(standing.id == myID ? Theme.fairway.opacity(0.08) : .clear)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 48)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func thruText(_ standing: TournamentStanding) -> String {
        guard let thru = standing.thru else { return "–" }
        if !standing.isPlaying && thru > 0 { return "F" }
        return "\(thru)"
    }
}

struct LeaderCard: View {
    let standing: TournamentStanding

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(avatar: standing.entrant.avatar, size: 54, showsRing: true)
                .overlay(alignment: .top) {
                    Image(systemName: "crown.fill").foregroundStyle(Theme.gold).offset(y: -14)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("Leader").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                Text(standing.entrant.name).font(.title3.weight(.bold))
                Text("\(standing.stats.birdiesOrBetter) birdies · GIR \(standing.stats.greensInRegulation.percentText) · \(standing.stats.puttsPerHole.map { String(format: "%.1f putts/hole", $0) } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .cardStyle()
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
                    VStack(alignment: .leading, spacing: 18) {
                        header(standing)
                        statsGrid(standing)
                        parAverages(standing)
                        ForEach(snapshot.tournament.rounds) { round in
                            if let pair = TournamentStandings.scorecard(for: entrantID, round: round.number, in: snapshot) {
                                let match = pair.0
                                let card = pair.1
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionHeader(title: "Round \(round.number)", subtitle: match.course.name)
                                    HoleByHoleChart(match: match, participant: card)
                                    ScorecardGrid(course: match.course, holes: match.holeNumbers, tee: match.tee,
                                                  players: [ScorecardPlayerRow(participant: card)], showsLengths: false, units: app.units)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }

    private func header(_ standing: TournamentStanding) -> some View {
        HStack(spacing: 16) {
            AvatarView(avatar: standing.entrant.avatar, size: 70, showsRing: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(standing.entrant.name).font(.title2.weight(.bold))
                HStack(spacing: 8) {
                    InfoPill(text: "Position \(standing.positionLabel)", systemImage: "list.number", tint: Theme.gold)
                    if let index = standing.entrant.handicapIndex {
                        InfoPill(text: "HCP \(HandicapCalculator.format(index))", tint: .secondary)
                    }
                }
                if standing.isPlaying, let hole = standing.currentHole {
                    Label("Playing hole \(hole) · thru \(standing.thru ?? 0)", systemImage: "figure.golf")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.fairway)
                }
            }
            Spacer()
            Text(standing.statusText).font(.rounded(32, weight: .heavy))
        }
    }

    private func statsGrid(_ standing: TournamentStanding) -> some View {
        let s = standing.stats
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            StatTile(title: "Holes", value: "\(s.holesPlayed)", systemImage: "flag")
            StatTile(title: "Birdies+", value: "\(s.birdiesOrBetter)", systemImage: "bird.fill", tint: Theme.flag)
            StatTile(title: "Bogey+", value: "\(s.count(.bogey) + s.count(.doubleBogey) + s.count(.tripleOrWorse))", systemImage: "arrow.down.right", tint: Theme.water)
            StatTile(title: "GIR", value: s.greensInRegulation.percentText, systemImage: "scope")
            StatTile(title: "Fairways", value: s.fairways.percentText, systemImage: "arrow.up.forward", tint: Theme.lime)
            StatTile(title: "Putts/hole", value: s.puttsPerHole.map { String(format: "%.2f", $0) } ?? "—", systemImage: "circle.dotted", tint: Theme.water)
        }
    }

    private func parAverages(_ standing: TournamentStanding) -> some View {
        HStack(spacing: 10) {
            ForEach([3, 4, 5], id: \.self) { par in
                StatTile(title: "Par \(par) avg", value: standing.stats.averageStrokes(onPar: par).map { String(format: "%.2f", $0) } ?? "—", systemImage: "\(par).circle", tint: Theme.gold)
            }
        }
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
                AreaMark(x: .value("Hole", point.index), y: .value("To par", point.cumulative))
                    .foregroundStyle(LinearGradient(colors: [Theme.fairway.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Hole", point.index), y: .value("To par", point.cumulative))
                    .foregroundStyle(Theme.fairway)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Hole", point.index), y: .value("To par", point.cumulative))
                    .foregroundStyle(point.diff < 0 ? Theme.flag : (point.diff == 0 ? Theme.fairway : Theme.water))
                    .symbolSize(point.diff == 0 ? 20 : 50)
                RuleMark(y: .value("Par", 0))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
            .cardStyle()
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
