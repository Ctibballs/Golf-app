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
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Section", selection: $section) {
                        ForEach(StatsSection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Group {
                        switch section {
                        case .overview: OverviewStats(gameType: gameType)
                        case .courses: CourseStatsList(gameType: gameType)
                        case .friends: FriendsStats(gameType: gameType)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(.snappySpring, value: section)
                .animation(.snappySpring, value: gameType)
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
                        Label(gameType.displayName, systemImage: gameType.symbolName)
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.semibold))
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
                .cardStyle()
        } else {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "Handicap", value: handicap.displayIndex, subtitle: handicap.source == .manual ? "Manual" : "\(handicap.eligibleRounds) scores", systemImage: "chart.line.uptrend.xyaxis")
                    StatTile(title: "Scoring avg", value: stats.scoringAverage.map { String(format: "%.1f", $0) } ?? "—", subtitle: "per 18 holes", systemImage: "sum", tint: Theme.water)
                    StatTile(title: "Best round", value: stats.bestRound.map { "\($0.totalStrokes)" } ?? "—", subtitle: stats.bestRound.map { "\(Leaderboard.formatToPar($0.toPar)) · \($0.course.name)" }, systemImage: "trophy.fill", tint: Theme.gold)
                    StatTile(title: "Rounds", value: "\(stats.rounds)", subtitle: "\(stats.scoring.holesPlayed) holes", systemImage: "flag.fill", tint: Theme.flag)
                }

                if stats.trend.count > 1 { TrendChart(points: stats.trend) }

                HStack(alignment: .top, spacing: 10) {
                    DistributionDonut(stats: stats.scoring)
                    VStack(spacing: 10) {
                        StatTile(title: "Putts / round", value: stats.scoring.puttsPerRound.map { String(format: "%.1f", $0) } ?? "—", systemImage: "circle.dotted", tint: Theme.water)
                        StatTile(title: "Shots to green", value: stats.scoring.averageShotsToGreen.map { String(format: "%.2f", $0) } ?? "—", subtitle: "per hole", systemImage: "arrow.up.right", tint: Theme.fairway)
                    }
                }

                if gameType.tracksGreens {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        StatTile(title: "GIR", value: stats.scoring.greensInRegulation.percentText, systemImage: "scope")
                        StatTile(title: "Scrambling", value: stats.scoring.scrambling.percentText, systemImage: "figure.run", tint: Theme.gold)
                        StatTile(title: "Sand saves", value: stats.scoring.sandSaves.percentText, systemImage: "beach.umbrella", tint: Theme.sand)
                        StatTile(title: "1-putts", value: "\(stats.scoring.onePutts)", systemImage: "1.circle", tint: Theme.lime)
                        StatTile(title: "3-putts", value: "\(stats.scoring.threePuttsOrWorse)", systemImage: "3.circle", tint: Theme.flag)
                        StatTile(title: "Penalties", value: String(format: "%.1f", Double(stats.scoring.penalties) / Double(max(1, stats.rounds))), subtitle: "per round", systemImage: "exclamationmark.triangle", tint: Theme.flag)
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

struct TrendChart: View {
    @Environment(AppModel.self) private var app
    let points: [TrendPoint]
    @State private var selected: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Score trend").font(.headline)
                Spacer()
                if let point = selectedPoint {
                    Text("\(point.courseName) · \(Leaderboard.formatToPar(point.toPar))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Text("Over par, per 18 holes").font(.caption).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Over par", point.toPar18))
                        .foregroundStyle(LinearGradient(colors: [Theme.fairway.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Date", point.date), y: .value("Over par", point.toPar18))
                        .foregroundStyle(Theme.fairway)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.date), y: .value("Over par", point.toPar18))
                        .foregroundStyle(Theme.fairway)
                        .symbolSize(30)
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Date", point.date))
                        .foregroundStyle(.secondary.opacity(0.4))
                    PointMark(x: .value("Date", point.date), y: .value("Over par", point.toPar18))
                        .foregroundStyle(Theme.flag)
                        .symbolSize(120)
                }
            }
            .chartXSelection(value: $selected)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 190)
            .animation(.snappySpring, value: selected)
        }
        .cardStyle()
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Scoring").font(.headline)
            Chart(slices) { slice in
                SectorMark(angle: .value("Holes", slice.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(slice.color)
                    .cornerRadius(4)
            }
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text("\(stats.holesPlayed)").font(.rounded(22, weight: .heavy))
                    Text("holes").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 130)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 7, height: 7)
                        Text(slice.name).font(.caption2)
                        Spacer()
                        Text("\(slice.count)").font(.caption2.weight(.bold))
                    }
                }
            }
        }
        .cardStyle(padding: 14)
    }

    private func makeSlices() -> [Slice] {
        let bar = ScoreDistributionBar(stats: stats)
        return [
            Slice(name: "Eagle+", count: stats.count(.albatrossOrBetter) + stats.count(.eagle), color: bar.color(.eagle)),
            Slice(name: "Birdie", count: stats.count(.birdie), color: bar.color(.birdie)),
            Slice(name: "Par", count: stats.count(.par), color: bar.color(.par)),
            Slice(name: "Bogey", count: stats.count(.bogey), color: bar.color(.bogey)),
            Slice(name: "Double+", count: stats.count(.doubleBogey) + stats.count(.tripleOrWorse), color: bar.color(.doubleBogey)),
        ].filter { $0.count > 0 }
    }
}

struct FairwayTendency: View {
    let stats: ScoringStats

    var body: some View {
        let total = max(1, stats.fairways.attempts)
        VStack(alignment: .leading, spacing: 12) {
            Text("Off the tee").font(.headline)
            HStack(spacing: 0) {
                column("Left", stats.fairwayMissLeft, total, systemImage: "arrow.up.left", tint: Theme.flag)
                column("Fairway", stats.fairways.made, total, systemImage: "checkmark", tint: Theme.fairway)
                column("Right", stats.fairwayMissRight, total, systemImage: "arrow.up.right", tint: Theme.flag)
            }
        }
        .cardStyle()
    }

    private func column(_ title: String, _ count: Int, _ total: Int, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.headline).foregroundStyle(tint)
            Text("\(Int((Double(count) / Double(total) * 100).rounded()))%").font(.rounded(24, weight: .bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Average over par by hole type").font(.headline)
                Chart(bars) { bar in
                    BarMark(x: .value("Par", "Par \(bar.par)"), y: .value("Over par", bar.average))
                        .foregroundStyle(bar.average <= 0 ? Theme.flag.gradient : Theme.water.gradient)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text(String(format: "%+.2f", bar.average)).font(.caption2.weight(.bold))
                        }
                }
                .frame(height: 150)
            }
            .cardStyle()
        }
    }
}

struct ClubDistanceChart: View {
    @Environment(AppModel.self) private var app
    let clubs: [ClubDistance]
    var averageDrive: Double?
    var longestDrive: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Club distances").font(.headline)
                Spacer()
                if let longestDrive {
                    InfoPill(text: "Longest drive \(app.units.distance(longestDrive))", systemImage: "flame.fill", tint: Theme.flag)
                }
            }
            Chart(clubs) { club in
                BarMark(x: .value("Distance", app.units.distanceValue(club.average)), y: .value("Club", club.club.shortName))
                    .foregroundStyle(Theme.fairway.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text(app.units.distance(club.average)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                PointMark(x: .value("Longest", app.units.distanceValue(club.longest)), y: .value("Club", club.club.shortName))
                    .foregroundStyle(Theme.gold)
                    .symbol(.diamond)
            }
            .chartXAxisLabel(app.units.system.distanceUnit)
            .frame(height: CGFloat(max(120, clubs.count * 34)))
            if let averageDrive {
                Text("Average drive \(app.units.distance(averageDrive)) · gold diamonds mark your longest with each club")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
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
                .cardStyle()
        } else {
            VStack(spacing: 10) {
                ForEach(courses) { course in
                    NavigationLink {
                        CourseStatsView(courseID: course.courseID)
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(course.courseName).font(.headline).lineLimit(1)
                                Text("\(course.roundsPlayed) round\(course.roundsPlayed == 1 ? "" : "s") · best \(course.bestRound.map { "\($0.totalStrokes)" } ?? "—")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HoleHeatStrip(holes: course.holes)
                                .frame(width: 110, height: 22)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                        .cardStyle(padding: 14)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

/// A row of tiny tiles coloured by average score to par per hole.
struct HoleHeatStrip: View {
    let holes: [HoleStats]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(holes) { hole in
                RoundedRectangle(cornerRadius: 2)
                    .fill(HoleHeatStrip.color(hole.averageToPar))
            }
        }
    }

    static func color(_ toPar: Double?) -> Color {
        guard let toPar else { return Color(uiColor: .tertiarySystemFill) }
        switch toPar {
        case ..<(-0.15): return Theme.flag
        case ..<0.25: return Theme.fairway
        case ..<0.75: return Theme.lime.opacity(0.8)
        case ..<1.25: return Theme.water.opacity(0.75)
        default: return Color(hex: 0x5E5CE6)
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
                .cardStyle()
        } else {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Friends leaderboard", subtitle: "Average over par per 18, across shared matches")
                    VStack(spacing: 0) {
                        ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                            HStack(spacing: 12) {
                                Text("\(index + 1)").font(.headline.monospacedDigit()).frame(width: 24).foregroundStyle(index == 0 ? Theme.gold : .secondary)
                                AvatarView(avatar: standing.avatar, size: 34, showsRing: standing.isMe)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(standing.isMe ? "You" : standing.name).font(.subheadline.weight(.semibold))
                                    Text("\(standing.rounds) rounds · GIR \(standing.stats.greensInRegulation.percentText) · \(standing.stats.puttsPerRound.map { String(format: "%.0f putts", $0) } ?? "")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(standing.averageToPar18.map { String(format: "%+.1f", $0) } ?? "—")
                                    .font(.headline.monospacedDigit())
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(standing.isMe ? Theme.fairway.opacity(0.08) : .clear)
                            if index < standings.count - 1 { Divider().padding(.leading, 48) }
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Head to head")
                    ForEach(records) { record in
                        NavigationLink {
                            HeadToHeadView(record: record)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(avatar: record.opponentAvatar, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("vs \(record.opponentName)").font(.headline)
                                    Text("\(record.matches.count) matches · holes \(record.holesWon)–\(record.holesLost)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(record.recordText)
                                    .font(.rounded(20, weight: .heavy))
                                    .foregroundStyle(record.wins > record.losses ? Theme.fairway : (record.wins < record.losses ? Theme.flag : .primary))
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                            .cardStyle(padding: 12)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }
}
