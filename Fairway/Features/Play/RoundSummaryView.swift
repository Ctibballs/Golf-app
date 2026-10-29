import SwiftUI
import Charts
import GolfKit

/// Shown when a round is finished: the headline score, key stats, the card and a replay.
struct RoundSummaryView: View {
    @Environment(AppModel.self) private var app
    let roundID: UUID
    var session: MatchSession?
    let onDone: () -> Void

    @State private var confetti = 0
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let round = app.round(roundID) {
                    VStack(spacing: 18) {
                        hero(round)
                        if let session {
                            MatchResultsCard(session: session)
                        }
                        RoundReport(round: round)
                    }
                    .padding()
                }
            }
            .background(Theme.background)
            .overlay { ConfettiView(trigger: confetti).ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone).fontWeight(.bold)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(.playful.delay(0.2)) { revealed = true }
                if isPersonalBest { confetti += 1 }
            }
        }
    }

    private var isPersonalBest: Bool {
        guard let round = app.round(roundID), round.isComplete else { return false }
        let others = app.library.completedRounds.filter {
            $0.id != round.id && $0.course.id == round.course.id && $0.holeNumbers.count == round.holeNumbers.count
        }
        return !others.isEmpty && others.allSatisfy { round.totalStrokes < $0.totalStrokes }
    }

    private func hero(_ round: Round) -> some View {
        VStack(spacing: 10) {
            if isPersonalBest {
                InfoPill(text: "Personal best", systemImage: "crown.fill", tint: .white)
            }
            Text("\(round.totalStrokes)")
                .font(.rounded(84, weight: .heavy))
                .contentTransition(.numericText(value: Double(revealed ? round.totalStrokes : 0)))
                .scaleEffect(revealed ? 1 : 0.6)
            Text(toParText(round.toPar))
                .font(.title3.weight(.bold))
                .opacity(0.9)
            Text("\(round.course.name) · \(round.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.gradient(for: round.gameType), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func toParText(_ toPar: Int) -> String {
        switch toPar {
        case 0: return "Level par"
        case ..<0: return "\(-toPar) under par"
        default: return "\(toPar) over par"
        }
    }
}

/// Final standings of a match.
struct MatchResultsCard: View {
    let session: MatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Results", subtitle: session.match.format.displayName)
            ForEach(session.leaderboard) { entry in
                HStack(spacing: 12) {
                    Text(entry.positionLabel)
                        .font(.headline.monospacedDigit())
                        .frame(width: 34)
                        .foregroundStyle(entry.position == 1 ? Theme.gold : .secondary)
                    AvatarView(avatar: entry.participant.avatar, size: 34)
                    Text(entry.participant.name).font(.subheadline.weight(.semibold))
                    if entry.position == 1 && entry.thru > 0 {
                        Image(systemName: "crown.fill").foregroundStyle(Theme.gold)
                    }
                    Spacer()
                    Text(entry.statusText).font(.headline)
                }
            }
        }
        .cardStyle()
    }
}

/// Stats, scorecard, handicap impact and replay link for a round. Shared by the summary
/// and the history detail screen.
struct RoundReport: View {
    @Environment(AppModel.self) private var app
    let round: Round

    var body: some View {
        let stats = StatsEngine.scoring(for: round)
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "Putts", value: round.totalPutts.map { "\($0)" } ?? "—", subtitle: stats.puttsPerHole.map { String(format: "%.1f / hole", $0) }, systemImage: "circle.dotted", tint: Theme.water)
                if round.gameType.tracksGreens {
                    StatTile(title: "Greens", value: stats.greensInRegulation.percentText, subtitle: "\(stats.greensInRegulation.made)/\(stats.greensInRegulation.attempts) in reg", systemImage: "scope")
                }
                if round.gameType.tracksFairways {
                    StatTile(title: "Fairways", value: stats.fairways.percentText, subtitle: "\(stats.fairways.made)/\(stats.fairways.attempts) hit", systemImage: "arrow.up.forward", tint: Theme.lime)
                }
                StatTile(title: "Birdies+", value: "\(stats.birdiesOrBetter)", systemImage: "bird.fill", tint: Theme.flag)
                StatTile(title: "Pars", value: "\(stats.count(.par))", systemImage: "equal.circle.fill")
                if round.gameType.tracksGreens {
                    StatTile(title: "Scrambling", value: stats.scrambling.percentText, systemImage: "figure.run", tint: Theme.gold)
                }
            }

            ScoreDistributionBar(stats: stats)

            if round.hasShotData {
                NavigationLink {
                    ReplayView(rounds: [round], course: round.course)
                } label: {
                    Label("Watch shot replay", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(gradient: Theme.skyGradient))
                ShotsToGreenChart(round: round)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Scorecard")
                ScorecardGrid(
                    course: round.course, holes: round.holeNumbers, tee: round.tee,
                    players: [ScorecardPlayerRow(round: round, avatar: round.playerID == app.profile.id ? app.profile.avatar : nil)],
                    units: app.units
                )
            }

            HandicapImpactCard(round: round)

            if let weather = round.weatherSummary {
                Label(weather, systemImage: "cloud.sun.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Eagles to doubles as a single stacked bar.
struct ScoreDistributionBar: View {
    let stats: ScoringStats

    var body: some View {
        let types = ScoreType.allCases.filter { stats.count($0) > 0 }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(types, id: \.self) { type in
                        Rectangle()
                            .fill(color(type))
                            .frame(width: max(4, geo.size.width * CGFloat(stats.count(type)) / CGFloat(max(1, stats.holesPlayed)) - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            HStack(spacing: 12) {
                ForEach(types, id: \.self) { type in
                    HStack(spacing: 4) {
                        Circle().fill(color(type)).frame(width: 8, height: 8)
                        Text("\(stats.count(type)) \(type.displayName)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    func color(_ type: ScoreType) -> Color {
        switch type {
        case .albatrossOrBetter, .eagle: return Theme.gold
        case .birdie: return Theme.flag
        case .par: return Theme.fairway
        case .bogey: return Theme.water
        case .doubleBogey: return Color(hex: 0x5E5CE6)
        case .tripleOrWorse: return Color(hex: 0x3A3A8C)
        }
    }
}

/// Shots to reach the green vs putts on each hole.
struct ShotsToGreenChart: View {
    let round: Round

    struct Bar: Identifiable {
        let hole: Int
        let kind: String
        let count: Int
        var id: String { "\(hole)-\(kind)" }
    }

    var body: some View {
        let bars: [Bar] = round.scores.flatMap { score -> [Bar] in
            guard let putts = score.putts else { return [] }
            return [Bar(hole: score.holeNumber, kind: "To green", count: score.strokes - putts), Bar(hole: score.holeNumber, kind: "Putts", count: putts)]
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("Shots to the green, then to the hole").font(.headline)
            Chart(bars) { bar in
                BarMark(x: .value("Hole", "\(bar.hole)"), y: .value("Strokes", bar.count))
                    .foregroundStyle(by: .value("Kind", bar.kind))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(["To green": Theme.fairway, "Putts": Theme.water])
            .frame(height: 160)
        }
        .cardStyle()
    }
}

/// How this round affects the handicap.
struct HandicapImpactCard: View {
    @Environment(AppModel.self) private var app
    let round: Round

    var body: some View {
        let result = app.handicap(for: round.gameType)
        let differential = result.differentials.first { $0.roundIDs.contains(round.id) }
        if let differential {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Score differential").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(String(format: "%.1f", differential.value)).font(.rounded(30, weight: .heavy))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if differential.usedInIndex {
                        InfoPill(text: "Counts toward index", systemImage: "checkmark.seal.fill", tint: Theme.fairway)
                    }
                    if differential.isEstimatedRating {
                        Text("Rating estimated from par").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("Index \(result.displayIndex)").font(.subheadline.weight(.bold))
                }
            }
            .cardStyle()
        } else if !round.countsForHandicap {
            Label("This round doesn't count toward your handicap.", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .cardStyle()
        }
    }
}

/// A past round from history.
struct RoundDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let roundID: UUID
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            if let round = app.round(roundID) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(round.totalStrokes)").font(.rounded(56, weight: .heavy))
                        ToParText(toPar: round.toPar, font: .title2.weight(.bold))
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(round.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                            if let tee = round.tee { Text("\(tee.name) tees").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if let record = app.library.matchHistory.first(where: { $0.id == round.matchID }) {
                        PastMatchCard(record: record)
                    }
                    RoundReport(round: round)
                }
                .padding()
            } else {
                EmptyStateView(title: "Round not found", message: "It may have been deleted.")
            }
        }
        .background(Theme.background)
        .navigationTitle(app.round(roundID)?.course.name ?? "Round")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let round = app.round(roundID) {
                        Toggle("Counts for handicap", isOn: Binding(
                            get: { round.countsForHandicap },
                            set: { value in
                                var updated = round
                                updated.countsForHandicap = value
                                app.saveRound(updated)
                            }
                        ))
                    }
                    Button("Delete round", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this round?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                app.deleteRound(roundID)
                dismiss()
            }
        }
    }
}

/// Everyone's scores from a saved match.
struct PastMatchCard: View {
    @Environment(AppModel.self) private var app
    let record: MatchRecord

    var body: some View {
        let entries = Leaderboard.entries(for: record.snapshot)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.snapshot.match.name).font(.headline)
                Spacer()
                InfoPill(text: record.snapshot.match.format.displayName, systemImage: record.snapshot.match.format.symbolName)
            }
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Text(entry.positionLabel).font(.subheadline.monospacedDigit()).frame(width: 28).foregroundStyle(.secondary)
                    AvatarView(avatar: entry.participant.avatar, size: 28)
                    Text(entry.participant.id == app.profile.id ? "You" : entry.participant.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(entry.gross)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Text(entry.statusText).font(.subheadline.weight(.bold)).frame(minWidth: 50, alignment: .trailing)
                }
            }
            if record.snapshot.participants.contains(where: { $0.scores.contains { !$0.shots.isEmpty } }) {
                NavigationLink {
                    ReplayView(
                        rounds: record.snapshot.participants.map { $0.round(in: record.snapshot.match) },
                        course: record.snapshot.match.course
                    )
                } label: {
                    Label("Replay everyone's shots", systemImage: "play.rectangle.on.rectangle.fill")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.water))
            }
        }
        .cardStyle()
    }
}
