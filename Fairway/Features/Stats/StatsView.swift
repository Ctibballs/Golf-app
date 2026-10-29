import SwiftUI
import Charts
import GolfKit

struct StatsView: View {
    @Environment(AppModel.self) private var app

    enum StatsSection: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case courses = "Courses"
        case friends = "Friends"
        var id: String { rawValue }
    }

    @State private var section: StatsSection = .overview
    @State private var gameType: GameType = .golf

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    UnderlineTabs(options: StatsSection.allCases, selection: $section) { $0.rawValue }

                    Group {
                        switch section {
                        case .overview: OverviewStats(gameType: gameType)
                        case .courses: CourseStatsList(gameType: gameType)
                        case .friends: FriendsStats(gameType: gameType)
                        }
                    }
                    .id(section)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
                .animation(.gentle, value: section)
                .animation(.gentle, value: gameType)
            }
            .background(Theme.background)
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Game", selection: $gameType) {
                            ForEach(GameType.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(gameType.displayName)
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
            .navigationDestination(for: Round.self) { RoundDetailView(roundID: $0.id) }
        }
    }
}

// MARK: - Overview

private struct OverviewStats: View {
    @Environment(AppModel.self) private var app
    let gameType: GameType

    var body: some View {
        let rounds = app.library.rounds.filter { $0.playerID == app.profile.id }
        let stats = StatsEngine.playerStats(rounds: rounds, gameType: gameType)
        let handicap = app.handicap(for: gameType)
        if stats.rounds == 0 {
            EmptyStateView(title: "No \(gameType.displayName.lowercased()) rounds yet", message: "Finish a round and your stats appear here.", systemImage: "chart.bar.xaxis")
        } else {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                MetricGrid(items: [
                    MetricItem(label: "Handicap", value: handicap.displayIndex, detail: handicapDetail(handicap)),
                    MetricItem(label: "Scoring avg", value: stats.scoringAverage.map { String(format: "%.1f", $0) } ?? "—", detail: "Per 18 holes"),
                    MetricItem(label: "Best round", value: stats.bestRound.map { "\($0.totalStrokes)" } ?? "—", detail: stats.bestRound.map { "\(Leaderboard.formatToPar($0.toPar)) · \($0.course.name)" }),
                    MetricItem(label: "Rounds", value: "\(stats.rounds)", detail: "\(stats.scoring.holesPlayed) holes"),
                ])
                .reveal(0)

                if stats.trend.count > 1 { TrendChart(points: stats.trend).reveal(1) }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Scoring")
                    DistributionDonut(stats: stats.scoring)
                    MetricGrid(items: [
                        MetricItem(label: "Putts / round", value: stats.scoring.puttsPerRound.map { String(format: "%.1f", $0) } ?? "—"),
                        MetricItem(label: "Shots to green", value: stats.scoring.averageShotsToGreen.map { String(format: "%.2f", $0) } ?? "—", detail: "Per hole"),
                    ])
                    .overlay(alignment: .top) { Hairline() }
                }

                if gameType.tracksGreens {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Around the green")
                        MetricGrid(items: [
                            MetricItem(label: "GIR", value: stats.scoring.greensInRegulation.percentText),
                            MetricItem(label: "Scrambling", value: stats.scoring.scrambling.percentText),
                            MetricItem(label: "Sand saves", value: stats.scoring.sandSaves.percentText),
                            MetricItem(label: "1-putts", value: "\(stats.scoring.onePutts)"),
                            MetricItem(label: "3-putts", value: "\(stats.scoring.threePuttsOrWorse)"),
                            MetricItem(label: "Penalties", value: String(format: "%.1f", Double(stats.scoring.penalties) / Double(max(1, stats.rounds))), detail: "Per round"),
                        ], columns: 3)
                    }
                }

                if gameType.tracksFairways && stats.scoring.fairways.attempts > 0 {
                    FairwayTendency(stats: stats.scoring)
                }

                ParAveragesChart(stats: stats.scoring, gameType: gameType)

                if !stats.clubDistances.isEmpty {
                    ClubDistanceChart(clubs: stats.clubDistances, averageDrive: stats.averageDrive, longestDrive: stats.longestDrive)
                }
            }
        }
    }
}

private func handicapDetail(_ result: HandicapResult) -> String {
    switch result.source {
    case .manual: return "Manual"
    case .off: return "Switched off"
    case .calculated, .notEstablished: return "\(result.eligibleRounds) scores"
    }
}

struct TrendChart: View {
    @Environment(AppModel.self) private var app
    let points: [TrendPoint]
    @State private var selected: Date?
    @State private var drawn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Score trend", subtitle: "Over par, per 18 holes") {
                if let point = selectedPoint {
                    Text("\(point.courseName) · \(Leaderboard.formatToPar(point.toPar))")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Over par", drawn ? point.toPar18 : minimum))
                        .foregroundStyle(LinearGradient(colors: [Theme.fairway.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", point.date), y: .value("Over par", drawn ? point.toPar18 : minimum))
                        .foregroundStyle(Theme.fairway)
                        .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Date", point.date))
                        .foregroundStyle(Theme.hairline)
                    PointMark(x: .value("Date", point.date), y: .value("Over par", point.toPar18))
                        .foregroundStyle(Theme.fairway)
                        .symbolSize(70)
                }
            }
            .chartXSelection(value: $selected)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 190)
            .animation(.snappySpring, value: selected)
            .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.15)) { drawn = true } }
        }
    }

    private var minimum: Double {
        points.map(\.toPar18).min() ?? 0
    }

    private var selectedPoint: TrendPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }
}

struct DistributionDonut: View {
    let stats: ScoringStats

    struct Slice: Identifiable {
        let name: String
        let count: Int
        let color: Color
        var id: String { name }
    }

    var body: some View {
        let slices = makeSlices()
        HStack(alignment: .center, spacing: 24) {
            Chart(slices) { slice in
                SectorMark(angle: .value("Holes", slice.count), innerRadius: .ratio(0.7), angularInset: 1)
                    .foregroundStyle(slice.color)
            }
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text("\(stats.holesPlayed)").font(.figure(20, weight: .semibold))
                    Eyebrow("Holes")
                }
            }
            .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    HStack(spacing: 8) {
                        Rectangle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.name).font(.subheadline)
                        Spacer()
                        Text("\(slice.count)").font(.figure(15, weight: .semibold))
                        Text(percent(slice.count)).font(.figure(13)).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    if index < slices.count - 1 { Hairline() }
                }
            }
        }
    }

    private func percent(_ count: Int) -> String {
        "\(Int((Double(count) / Double(max(1, stats.holesPlayed)) * 100).rounded()))%"
    }

    private func makeSlices() -> [Slice] {
        [
            Slice(name: "Eagle+", count: stats.count(.albatrossOrBetter) + stats.count(.eagle), color: ScoreDistributionBar.color(.eagle)),
            Slice(name: "Birdie", count: stats.count(.birdie), color: ScoreDistributionBar.color(.birdie)),
            Slice(name: "Par", count: stats.count(.par), color: ScoreDistributionBar.color(.par)),
            Slice(name: "Bogey", count: stats.count(.bogey), color: ScoreDistributionBar.color(.bogey)),
            Slice(name: "Double+", count: stats.count(.doubleBogey) + stats.count(.tripleOrWorse), color: ScoreDistributionBar.color(.doubleBogey)),
        ].filter { $0.count > 0 }
    }
}

struct FairwayTendency: View {
    let stats: ScoringStats

    var body: some View {
        let total = max(1, stats.fairways.attempts)
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Off the tee", subtitle: "\(stats.fairways.attempts) tee shots on par 4s and 5s")
            HStack(spacing: 0) {
                column("Missed left", stats.fairwayMissLeft, total, systemImage: "arrow.up.left", tint: .secondary)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                column("Fairway", stats.fairways.made, total, systemImage: "arrow.up", tint: Theme.fairway)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                column("Missed right", stats.fairwayMissRight, total, systemImage: "arrow.up.right", tint: .secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func column(_ title: String, _ count: Int, _ total: Int, systemImage: String, tint: Color) -> some View {
        let fraction = Double(count) / Double(total)
        return VStack(spacing: 6) {
            Image(systemName: systemImage).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            Text("\(Int((fraction * 100).rounded()))%").font(.figure(24))
            Text(title).font(.caption).foregroundStyle(.secondary)
            ProgressLine(fraction: fraction, tint: tint)
                .padding(.horizontal, 18)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct ParAveragesChart: View {
    let stats: ScoringStats
    let gameType: GameType

    struct Bar: Identifiable {
        let par: Int
        let average: Double
        var id: Int { par }
    }

    var body: some View {
        let bars = Array(gameType.allowedPars).compactMap { par in stats.averageStrokes(onPar: par).map { Bar(par: par, average: $0 - Double(par)) } }
        if !bars.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Average over par by hole type")
                Chart(bars) { bar in
                    BarMark(x: .value("Par", "Par \(bar.par)"), y: .value("Over par", bar.average), width: .ratio(0.4))
                        .foregroundStyle(bar.average <= 0 ? Theme.flag : Theme.water)
                        .annotation(position: .top) {
                            Text(String(format: "%+.2f", bar.average)).font(.caption.weight(.medium)).monospacedDigit()
                        }
                }
                .frame(height: 150)
            }
        }
    }
}

struct ClubDistanceChart: View {
    @Environment(AppModel.self) private var app
    let clubs: [ClubDistance]
    var averageDrive: Double?
    var longestDrive: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Club distances", subtitle: longestDrive.map { "Longest drive \(app.units.distance($0))" })
            Chart(clubs) { club in
                BarMark(x: .value("Distance", app.units.distanceValue(club.average)), y: .value("Club", club.club.shortName), height: .ratio(0.45))
                    .foregroundStyle(Theme.fairway)
                    .annotation(position: .trailing) {
                        Text(app.units.distance(club.average)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                PointMark(x: .value("Longest", app.units.distanceValue(club.longest)), y: .value("Club", club.club.shortName))
                    .foregroundStyle(Theme.gold)
                    .symbol(.diamond)
                    .symbolSize(30)
            }
            .chartXAxisLabel(app.units.system.distanceUnit)
            .frame(height: CGFloat(max(120, clubs.count * 32)))
            if let averageDrive {
                Text("Average drive \(app.units.distance(averageDrive)). Diamonds mark your longest with each club.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Courses

private struct CourseStatsList: View {
    @Environment(AppModel.self) private var app
    let gameType: GameType

    var body: some View {
        let rounds = app.library.rounds.filter { $0.playerID == app.profile.id && $0.gameType == gameType }
        let courses = StatsEngine.courseStats(rounds: rounds)
        if courses.isEmpty {
            EmptyStateView(title: "No courses yet", message: "Per-course and per-hole stats build up as you play.", systemImage: "map")
        } else {
            DividedList(courses) { course in
                NavigationLink {
                    CourseStatsView(courseID: course.courseID)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.courseName).font(.body.weight(.medium)).lineLimit(1)
                                Text("\(course.roundsPlayed) round\(course.roundsPlayed == 1 ? "" : "s") · best \(course.bestRound.map { "\($0.totalStrokes)" } ?? "—")")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        HoleHeatStrip(holes: course.holes)
                            .frame(height: 10)
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

/// A row of small tiles coloured by average score to par per hole.
struct HoleHeatStrip: View {
    let holes: [HoleStats]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(holes) { hole in
                Rectangle()
                    .fill(HoleHeatStrip.color(hole.averageToPar))
            }
        }
    }

    static func color(_ toPar: Double?) -> Color {
        guard let toPar else { return Theme.fill }
        switch toPar {
        case ..<(-0.15): return Theme.flag
        case ..<0.25: return Theme.fairway
        case ..<0.75: return Theme.fairway.opacity(0.45)
        case ..<1.25: return Theme.water.opacity(0.7)
        default: return Theme.double
        }
    }
}

// MARK: - Friends

private struct FriendsStats: View {
    @Environment(AppModel.self) private var app
    let gameType: GameType

    var body: some View {
        let history = app.library.matchHistory
        let standings = HeadToHeadEngine.friendsLeaderboard(for: app.profile.id, in: history, gameType: gameType)
        let records = HeadToHeadEngine.records(for: app.profile.id, in: history.filter { $0.snapshot.match.course.gameType == gameType })
        if records.isEmpty {
            EmptyStateView(title: "Play a match with friends", message: "Head-to-head records and comparisons appear after your first match.", systemImage: "person.2")
        } else {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Friends leaderboard", subtitle: "Average over par per 18, across shared matches")
                    DividedList(Array(standings.enumerated()).map { RankedStanding(rank: $0.offset + 1, standing: $0.element) }, inset: 40) { item in
                        let standing = item.standing
                        HStack(spacing: 12) {
                            Text("\(item.rank)")
                                .font(.figure(15, weight: .semibold))
                                .frame(width: 24, alignment: .leading)
                                .foregroundStyle(item.rank == 1 ? Theme.gold : .secondary)
                            AvatarView(avatar: standing.avatar, size: 32, showsRing: standing.isMe)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(standing.isMe ? "You" : standing.name).font(.body.weight(standing.isMe ? .semibold : .medium))
                                Text("\(standing.rounds) rounds · GIR \(standing.stats.greensInRegulation.percentText) · \(standing.stats.puttsPerRound.map { String(format: "%.0f putts", $0) } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(standing.averageToPar18.map { String(format: "%+.1f", $0) } ?? "—")
                                .font(.figure(17, weight: .semibold))
                        }
                        .padding(.vertical, 10)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Head to head")
                    DividedList(records, inset: 52) { record in
                        NavigationLink {
                            HeadToHeadView(record: record)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(avatar: record.opponentAvatar, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("vs \(record.opponentName)").font(.body.weight(.medium))
                                    Text("\(record.matches.count) matches · holes \(record.holesWon)–\(record.holesLost)")
                                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                                }
                                Spacer()
                                Text(record.recordText)
                                    .font(.figure(18, weight: .semibold))
                                    .foregroundStyle(record.wins > record.losses ? Theme.fairway : (record.wins < record.losses ? Theme.flag : .primary))
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }
}

private struct RankedStanding: Identifiable {
    let rank: Int
    let standing: FriendStanding
    var id: FriendStanding.ID { standing.id }
}
