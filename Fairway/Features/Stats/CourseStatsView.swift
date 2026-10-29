import SwiftUI
import Charts
import GolfKit

/// Per-hole breakdown at one course: averages, bests, hardest and easiest holes.
struct CourseStatsView: View {
    @Environment(AppModel.self) private var app
    let courseID: String
    @State private var selectedHole: HoleStats?

    var body: some View {
        let rounds = app.library.rounds.filter { $0.course.id == courseID && $0.playerID == app.profile.id }
        ScrollView {
            if let stats = StatsEngine.courseStats(rounds: rounds).first {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Course stats")
                        Text(stats.courseName).font(.display(28)).lineLimit(2)
                        MetricGrid(items: [
                            MetricItem(label: "Rounds", value: "\(stats.roundsPlayed)"),
                            MetricItem(label: "Average", value: stats.averageScore.map { String(format: "%.1f", $0) } ?? "—"),
                            MetricItem(label: "Best", value: stats.bestRound.map { "\($0.totalStrokes)" } ?? "—"),
                        ], columns: 3)
                        .padding(.top, 8)
                        .overlay(alignment: .top) { Hairline().padding(.top, 8) }
                    }
                    .reveal(0)

                    holeGrid(stats).reveal(1)

                    if let hardest = stats.holesByDifficulty.first, let easiest = stats.holesByDifficulty.last, hardest.number != easiest.number {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Toughest and easiest")
                            MetricGrid(items: [
                                MetricItem(label: "Toughest", value: "Hole \(hardest.number)", detail: "Par \(hardest.par) · avg \(hardest.averageToPar.map { String(format: "%+.2f", $0) } ?? "—")", tint: Theme.water),
                                MetricItem(label: "Easiest", value: "Hole \(easiest.number)", detail: "Par \(easiest.par) · avg \(easiest.averageToPar.map { String(format: "%+.2f", $0) } ?? "—")", tint: Theme.flag),
                            ])
                        }
                    }

                    holeChart(stats)

                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Rounds here")
                        DividedList(stats.rounds) { round in
                            NavigationLink(value: round) { RoundRow(round: round) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            } else {
                EmptyStateView(title: "No rounds here yet", message: "Play this course to see hole-by-hole stats.")
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedHole) { hole in
            HoleStatsSheet(hole: hole)
        }
    }

    private func holeGrid(_ stats: CourseStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Hole by hole", subtitle: "Your average score; colour shows how it compares with par")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 0) {
                ForEach(stats.holes) { hole in
                    Button { selectedHole = hole } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(hole.number)").font(.eyebrow).foregroundStyle(.secondary)
                            Text(hole.averageStrokes.map { String(format: "%.1f", $0) } ?? "–")
                                .font(.figure(17, weight: .semibold))
                                .foregroundStyle(hole.timesPlayed > 0 ? .primary : .tertiary)
                            Rectangle()
                                .fill(HoleHeatStrip.color(hole.averageToPar))
                                .frame(height: 3)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Hairline() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private func holeChart(_ stats: CourseStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Average over par")
            Chart(stats.holes.filter { $0.timesPlayed > 0 }) { hole in
                BarMark(x: .value("Hole", "\(hole.number)"), y: .value("Over par", hole.averageToPar ?? 0), width: .ratio(0.6))
                    .foregroundStyle(HoleHeatStrip.color(hole.averageToPar))
            }
            .frame(height: 160)
        }
    }
}

struct HoleStatsSheet: View {
    let hole: HoleStats

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Par \(hole.par)\(hole.strokeIndex.map { " · stroke index \($0)" } ?? "")")
                Text("Hole \(hole.number)").font(.display(30))
            }
            MetricGrid(items: [
                MetricItem(label: "Played", value: "\(hole.timesPlayed)"),
                MetricItem(label: "Average", value: hole.averageStrokes.map { String(format: "%.2f", $0) } ?? "—"),
                MetricItem(label: "Best", value: hole.best.map { "\($0)" } ?? "—"),
                MetricItem(label: "Putts", value: hole.scoring.puttsPerHole.map { String(format: "%.1f", $0) } ?? "—"),
                MetricItem(label: "GIR", value: hole.scoring.greensInRegulation.percentText),
                MetricItem(label: "Birdies+", value: "\(hole.scoring.birdiesOrBetter)"),
            ], columns: 3)
            .overlay(alignment: .top) { Hairline() }
            ScoreDistributionBar(stats: hole.scoring)
            Spacer()
        }
        .padding(Theme.gutter)
        .padding(.top, 8)
        .background(Theme.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

/// You vs one friend.
struct HeadToHeadView: View {
    @Environment(AppModel.self) private var app
    let record: HeadToHeadRecord
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                versusHeader
                comparison
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Matches")
                    DividedList(record.matches, inset: 32) { match in
                        HStack(spacing: 12) {
                            Text(outcomeLetter(match.outcome))
                                .font(.figure(15, weight: .bold))
                                .foregroundStyle(outcomeColor(match.outcome))
                                .frame(width: 20, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.courseName).font(.body.weight(.medium))
                                Text("\(match.date.formatted(date: .abbreviated, time: .omitted)) · \(match.holesCompared) holes")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(match.myStrokes) – \(match.theirStrokes)").font(.figure(16, weight: .semibold))
                        }
                        .padding(.vertical, 11)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationTitle("Head to head")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { withAnimation(.snappySpring.delay(0.1)) { appeared = true } }
    }

    private var versusHeader: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center) {
                VStack(spacing: 8) {
                    AvatarView(avatar: app.profile.avatar, size: 60, showsRing: true)
                    Text("You").font(.subheadline.weight(.medium))
                }
                .frame(width: 90)
                .offset(x: appeared ? 0 : -24)
                .opacity(appeared ? 1 : 0)
                Spacer()
                VStack(spacing: 4) {
                    Text(record.recordText)
                        .font(.display(40, weight: .regular))
                        .monospacedDigit()
                    Eyebrow("Won – lost – halved")
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.92)
                Spacer()
                VStack(spacing: 8) {
                    AvatarView(avatar: record.opponentAvatar, size: 60)
                    Text(record.opponentName).font(.subheadline.weight(.medium)).lineLimit(1)
                }
                .frame(width: 90)
                .offset(x: appeared ? 0 : 24)
                .opacity(appeared ? 1 : 0)
            }
            MetricGrid(items: [
                MetricItem(label: "Holes won", value: "\(record.holesWon)", tint: Theme.fairway),
                MetricItem(label: "Lost", value: "\(record.holesLost)"),
                MetricItem(label: "Halved", value: "\(record.holesHalved)"),
            ], columns: 3, compact: true)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
            if let margin = record.averageMarginPer18 {
                Text(margin >= 0 ? String(format: "You average %.1f shots better per 18 holes.", margin) : String(format: "%@ averages %.1f shots better per 18 holes.", record.opponentName, -margin))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 8)
    }

    private var comparison: some View {
        let me = record.myStats, them = record.theirStats
        return VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Stat by stat") {
                HStack(spacing: 12) {
                    legend("You", Theme.fairway)
                    legend(record.opponentName, Theme.water)
                }
            }
            ComparisonBar(label: "Avg over par / 18", mine: me.averageToParPerHole.map { $0 * 18 }, theirs: them.averageToParPerHole.map { $0 * 18 }, format: { String(format: "%+.1f", $0) }, lowerIsBetter: true)
            ComparisonBar(label: "Greens in regulation", mine: me.greensInRegulation.fraction.map { $0 * 100 }, theirs: them.greensInRegulation.fraction.map { $0 * 100 }, format: { "\(Int($0.rounded()))%" })
            ComparisonBar(label: "Fairways", mine: me.fairways.fraction.map { $0 * 100 }, theirs: them.fairways.fraction.map { $0 * 100 }, format: { "\(Int($0.rounded()))%" })
            ComparisonBar(label: "Putts per hole", mine: me.puttsPerHole, theirs: them.puttsPerHole, format: { String(format: "%.2f", $0) }, lowerIsBetter: true)
            ComparisonBar(label: "Birdies or better", mine: Double(me.birdiesOrBetter), theirs: Double(them.birdiesOrBetter), format: { "\(Int($0))" })
            ComparisonBar(label: "Scrambling", mine: me.scrambling.fraction.map { $0 * 100 }, theirs: them.scrambling.fraction.map { $0 * 100 }, format: { "\(Int($0.rounded()))%" })
        }
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func outcomeLetter(_ outcome: HeadToHeadOutcome) -> String {
        switch outcome {
        case .win: return "W"
        case .loss: return "L"
        default: return "H"
        }
    }

    private func outcomeColor(_ outcome: HeadToHeadOutcome) -> Color {
        switch outcome {
        case .win: return Theme.fairway
        case .loss: return Theme.flag
        default: return .secondary
        }
    }
}
