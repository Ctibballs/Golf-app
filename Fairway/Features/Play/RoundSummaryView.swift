import SwiftUI
import Charts
import GolfKit

/// Shown when a round is finished: the headline score, key stats, the card and a replay.
struct RoundSummaryView: View {
    @Environment(AppModel.self) private var app
    let roundID: UUID
    var session: MatchSession?
    let onDone: () -> Void

    @State private var shownStrokes = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                if let round = app.round(roundID) {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        hero(round)
                        if let session {
                            let model = ResultsCardModel(snapshot: session.snapshot)
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Results", subtitle: "\(model.entries.count) players")
                                ResultsCard(model: model, units: app.units)
                                ShareScorecardButton(model: model, units: app.units)
                                    .buttonStyle(SecondaryButtonStyle(tint: Theme.fairway))
                            }
                            .reveal(1)
                        } else {
                            ShareScorecardButton(model: ResultsCardModel(round: round, avatar: app.profile.avatar), units: app.units)
                                .buttonStyle(SecondaryButtonStyle(tint: Theme.fairway))
                        }
                        RoundReport(round: round, showsScorecard: session == nil)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 32)
                }
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone).fontWeight(.semibold)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard let round = app.round(roundID) else { return }
                // Count the score up from par so the digits roll into place.
                shownStrokes = round.course.par(for: round.holeNumbers)
                withAnimation(.easeOut(duration: 0.9).delay(0.25)) { shownStrokes = round.totalStrokes }
            }
            .sensoryFeedback(.success, trigger: shownStrokes == app.round(roundID)?.totalStrokes) { _, done in done && isPersonalBest }
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
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Round complete · \(round.date.formatted(date: .abbreviated, time: .omitted))")
            Text(round.course.name)
                .font(.display(28))
                .lineLimit(2)
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text("\(shownStrokes)")
                    .font(.display(96, weight: .regular))
                    .contentTransition(.numericText(value: Double(shownStrokes)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(toParText(round.toPar))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(round.toPar < 0 ? Theme.flag : .primary)
                    if isPersonalBest {
                        Label("Personal best", systemImage: "crown.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                            .symbolEffect(.bounce, value: shownStrokes == round.totalStrokes)
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .padding(.top, 8)
        .reveal(0)
    }

    private func toParText(_ toPar: Int) -> String {
        switch toPar {
        case 0: return "Level par"
        case ..<0: return "\(-toPar) under par"
        default: return "\(toPar) over par"
        }
    }
}

/// Stats, scorecard, handicap impact and replay link for a round. Shared by the summary
/// and the history detail screen.
struct RoundReport: View {
    @Environment(AppModel.self) private var app
    let round: Round
    /// Off when a results card above already shows everyone's card.
    var showsScorecard = true

    var body: some View {
        let stats = StatsEngine.scoring(for: round)
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Round stats")
                MetricGrid(items: metrics(stats), columns: 3)
                ScoreDistributionBar(stats: stats)
                    .padding(.top, 4)
            }
            .reveal(1)

            if round.hasShotData {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Shots to the green, then to the hole")
                    ShotsToGreenChart(round: round)
                    NavigationLink {
                        ReplayView(rounds: [round], course: round.course)
                    } label: {
                        Label("Watch shot replay", systemImage: "play.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.fairway))
                }
            }

            if showsScorecard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Scorecard")
                    ScorecardGrid(
                        course: round.course, holes: round.holeNumbers, tee: round.tee,
                        players: [ScorecardPlayerRow(round: round, avatar: round.playerID == app.profile.id ? app.profile.avatar : nil)],
                        units: app.units
                    )
                }
            }

            HandicapImpactSection(round: round)

            if let weather = round.weatherSummary {
                Label(weather, systemImage: "cloud.sun")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metrics(_ stats: ScoringStats) -> [MetricItem] {
        var items = [
            MetricItem(label: "Putts", value: round.totalPutts.map { "\($0)" } ?? "—", detail: stats.puttsPerHole.map { String(format: "%.1f per hole", $0) }),
        ]
        if round.gameType.tracksGreens {
            items.append(MetricItem(label: "Greens", value: stats.greensInRegulation.percentText, detail: "\(stats.greensInRegulation.made) of \(stats.greensInRegulation.attempts)"))
        }
        if round.gameType.tracksFairways {
            items.append(MetricItem(label: "Fairways", value: stats.fairways.percentText, detail: "\(stats.fairways.made) of \(stats.fairways.attempts)"))
        }
        items.append(MetricItem(label: "Birdies+", value: "\(stats.birdiesOrBetter)", tint: stats.birdiesOrBetter > 0 ? Theme.flag : nil))
        items.append(MetricItem(label: "Pars", value: "\(stats.count(.par))"))
        if round.gameType.tracksGreens {
            items.append(MetricItem(label: "Scrambling", value: stats.scrambling.percentText))
        }
        return items
    }
}

/// Eagles to doubles as a single stacked bar with a legend.
struct ScoreDistributionBar: View {
    let stats: ScoringStats
    @State private var shown = false

    var body: some View {
        let types = ScoreType.allCases.filter { stats.count($0) > 0 }
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(types, id: \.self) { type in
                        Rectangle()
                            .fill(Self.color(type))
                            .frame(width: max(3, geo.size.width * CGFloat(stats.count(type)) / CGFloat(max(1, stats.holesPlayed)) - 2))
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .scaleEffect(x: shown ? 1 : 0, anchor: .leading)
            }
            .frame(height: 6)
            HStack(spacing: 14) {
                ForEach(types, id: \.self) { type in
                    HStack(spacing: 5) {
                        Rectangle().fill(Self.color(type)).frame(width: 8, height: 8)
                        Text("\(stats.count(type))").font(.caption.weight(.semibold)).monospacedDigit()
                        Text(type.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.2)) { shown = true } }
    }

    static func color(_ type: ScoreType) -> Color {
        switch type {
        case .albatrossOrBetter, .eagle: return Theme.gold
        case .birdie: return Theme.flag
        case .par: return Color.primary.opacity(0.75)
        case .bogey: return Theme.water
        case .doubleBogey: return Theme.double
        case .tripleOrWorse: return Theme.double.opacity(0.6)
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
        Chart(bars) { bar in
            BarMark(x: .value("Hole", "\(bar.hole)"), y: .value("Strokes", bar.count), width: .ratio(0.55))
                .foregroundStyle(by: .value("Kind", bar.kind))
        }
        .chartForegroundStyleScale(["To green": Theme.fairway, "Putts": Theme.water.opacity(0.55)])
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 170)
    }
}

/// How this round affects the handicap.
struct HandicapImpactSection: View {
    @Environment(AppModel.self) private var app
    let round: Round

    var body: some View {
        let result = app.handicap(for: round.gameType)
        let differential = result.differentials.first { $0.roundIDs.contains(round.id) }
        if let differential {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Handicap")
                MetricGrid(items: [
                    MetricItem(label: "Differential", value: String(format: "%.1f", differential.value),
                               detail: differential.isEstimatedRating ? "Rating estimated from par" : (differential.usedInIndex ? "Counts toward index" : "Not in your best scores"),
                               tint: differential.usedInIndex ? Theme.fairway : nil),
                    MetricItem(label: "Index now", value: result.displayIndex),
                ], columns: 2)
            }
        } else if !round.countsForHandicap {
            Label("This round doesn't count toward your handicap.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(round.date.formatted(date: .long, time: .shortened))
                        Text(round.course.name).font(.display(28)).lineLimit(2)
                        HStack(alignment: .lastTextBaseline, spacing: 12) {
                            Text("\(round.totalStrokes)").font(.display(64, weight: .regular))
                            ToParText(toPar: round.toPar, font: .title3.weight(.medium))
                            Spacer()
                            if let tee = round.tee {
                                Text("\(tee.name) tees").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .reveal(0)
                    let record = app.library.matchHistory.first(where: { $0.id == round.matchID })
                    if let record {
                        PastMatchSection(record: record)
                    } else {
                        ShareScorecardButton(model: ResultsCardModel(round: round, avatar: round.playerID == app.profile.id ? app.profile.avatar : nil), units: app.units)
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.fairway))
                    }
                    RoundReport(round: round, showsScorecard: record == nil)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            } else {
                EmptyStateView(title: "Round not found", message: "It may have been deleted.")
            }
        }
        .background(Theme.background)
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

/// Everyone's scores from a saved match, with the podium and a way to share them.
struct PastMatchSection: View {
    @Environment(AppModel.self) private var app
    let record: MatchRecord

    var body: some View {
        let model = ResultsCardModel(snapshot: record.snapshot)
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Results", subtitle: "\(model.entries.count) players")
            ResultsCard(model: model, units: app.units)
            ShareScorecardButton(model: model, units: app.units)
                .buttonStyle(SecondaryButtonStyle(tint: Theme.fairway))
            if record.snapshot.participants.contains(where: { $0.scores.contains { !$0.shots.isEmpty } }) {
                NavigationLink {
                    ReplayView(
                        rounds: record.snapshot.participants.map { $0.round(in: record.snapshot.match) },
                        course: record.snapshot.match.course
                    )
                } label: {
                    Label("Replay everyone's shots", systemImage: "play.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
