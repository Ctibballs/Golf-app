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
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        StatTile(title: "Rounds", value: "\(stats.roundsPlayed)", systemImage: "flag.fill")
                        StatTile(title: "Average", value: stats.averageScore.map { String(format: "%.1f", $0) } ?? "—", systemImage: "sum", tint: Theme.water)
                        StatTile(title: "Best", value: stats.bestRound.map { "\($0.totalStrokes)" } ?? "—", systemImage: "trophy.fill", tint: Theme.gold)
                    }

                    holeGrid(stats)

                    if let hardest = stats.holesByDifficulty.first, let easiest = stats.holesByDifficulty.last, hardest.number != easiest.number {
                        HStack(spacing: 10) {
                            extremeCard(title: "Toughest", hole: hardest, tint: Theme.water)
                            extremeCard(title: "Easiest", hole: easiest, tint: Theme.flag)
                        }
                    }

                    holeChart(stats)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Rounds here")
                        ForEach(stats.rounds) { round in
                            NavigationLink(value: round) { RoundRow(round: round) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding()
            } else {
                EmptyStateView(title: "No rounds here yet", message: "Play this course to see hole-by-hole stats.")
            }
        }
        .background(Theme.background)
        .navigationTitle(rounds.first?.course.name ?? "Course")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedHole) { hole in
            HoleStatsSheet(hole: hole)
        }
    }

    private func holeGrid(_ stats: CourseStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Hole by hole", subtitle: "Colour shows your average against par")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(stats.holes) { hole in
                    Button { selectedHole = hole } label: {
                        VStack(spacing: 2) {
                            Text("\(hole.number)").font(.caption2.weight(.bold)).opacity(0.8)
                            Text(hole.averageStrokes.map { String(format: "%.1f", $0) } ?? "–")
                                .font(.rounded(17, weight: .heavy))
                            Text("par \(hole.par)").font(.system(size: 9, weight: .semibold)).opacity(0.8)
                        }
                        .foregroundStyle(hole.timesPlayed > 0 ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(HoleHeatStrip.color(hole.averageToPar), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func extremeCard(title: String, hole: HoleStats, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(tint)
            Text("Hole \(hole.number)").font(.title3.weight(.bold))
            Text("Par \(hole.par) · avg \(hole.averageToPar.map { String(format: "%+.2f", $0) } ?? "—")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func holeChart(_ stats: CourseStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Average over par").font(.headline)
            Chart(stats.holes.filter { $0.timesPlayed > 0 }) { hole in
                BarMark(x: .value("Hole", "\(hole.number)"), y: .value("Over par", hole.averageToPar ?? 0))
                    .foregroundStyle(HoleHeatStrip.color(hole.averageToPar))
                    .cornerRadius(3)
            }
            .frame(height: 160)
        }
        .cardStyle()
    }
}

struct HoleStatsSheet: View {
    let hole: HoleStats

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Hole \(hole.number)").font(.rounded(30, weight: .heavy))
                Spacer()
                InfoPill(text: "Par \(hole.par)", systemImage: "flag")
                if let si = hole.strokeIndex { InfoPill(text: "S.I. \(si)") }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "Played", value: "\(hole.timesPlayed)", systemImage: "number")
                StatTile(title: "Average", value: hole.averageStrokes.map { String(format: "%.2f", $0) } ?? "—", systemImage: "sum", tint: Theme.water)
                StatTile(title: "Best", value: hole.best.map { "\($0)" } ?? "—", systemImage: "trophy.fill", tint: Theme.gold)
                StatTile(title: "Putts", value: hole.scoring.puttsPerHole.map { String(format: "%.1f", $0) } ?? "—", systemImage: "circle.dotted", tint: Theme.water)
                StatTile(title: "GIR", value: hole.scoring.greensInRegulation.percentText, systemImage: "scope")
                StatTile(title: "Birdies+", value: "\(hole.scoring.birdiesOrBetter)", systemImage: "bird.fill", tint: Theme.flag)
            }
            ScoreDistributionBar(stats: hole.scoring)
            Spacer()
        }
        .padding()
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
            VStack(spacing: 18) {
                versusHeader
                comparison
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Matches")
                    ForEach(record.matches) { match in
                        HStack(spacing: 12) {
                            Image(systemName: match.outcome == .win ? "checkmark.circle.fill" : (match.outcome == .loss ? "xmark.circle.fill" : "equal.circle.fill"))
                                .font(.title3)
                                .foregroundStyle(match.outcome == .win ? Theme.fairway : (match.outcome == .loss ? Theme.flag : .secondary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.courseName).font(.subheadline.weight(.semibold))
                                Text("\(match.date.formatted(date: .abbreviated, time: .omitted)) · \(match.holesCompared) holes")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(match.myStrokes) – \(match.theirStrokes)").font(.headline.monospacedDigit())
                        }
                        .cardStyle(padding: 12)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Head to head")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { withAnimation(.playful.delay(0.1)) { appeared = true } }
    }

    private var versusHeader: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(spacing: 6) {
                    AvatarView(avatar: app.profile.avatar, size: 64, showsRing: true)
                    Text("You").font(.headline)
                }
                .offset(x: appeared ? 0 : -60)
                Spacer()
                VStack(spacing: 2) {
                    Text(record.recordText).font(.rounded(36, weight: .heavy))
                    Text("W – L – T").font(.caption2.weight(.bold)).opacity(0.8)
                }
                .scaleEffect(appeared ? 1 : 0.5)
                Spacer()
                VStack(spacing: 6) {
                    AvatarView(avatar: record.opponentAvatar, size: 64, showsRing: true)
                    Text(record.opponentName).font(.headline)
                }
                .offset(x: appeared ? 0 : 60)
            }
            HStack(spacing: 8) {
                InfoPill(text: "Holes won \(record.holesWon)", tint: .white)
                InfoPill(text: "Lost \(record.holesLost)", tint: .white)
                InfoPill(text: "Halved \(record.holesHalved)", tint: .white)
            }
            if let margin = record.averageMarginPer18 {
                Text(margin >= 0 ? String(format: "You average %.1f shots better per 18", margin) : String(format: "%@ averages %.1f shots better per 18", record.opponentName, -margin))
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var comparison: some View {
        let me = record.myStats, them = record.theirStats
        return VStack(spacing: 16) {
            HStack {
                Text("You").font(.caption.weight(.heavy)).foregroundStyle(Theme.fairway)
                Spacer()
                Text(record.opponentName).font(.caption.weight(.heavy)).foregroundStyle(Theme.water)
            }
            ComparisonBar(label: "Avg over par / 18", mine: me.averageToParPerHole.map { $0 * 18 }, theirs: them.averageToParPerHole.map { $0 * 18 }, format: { String(format: "%+.1f", $0) }, lowerIsBetter: true)
            ComparisonBar(label: "Greens in reg", mine: me.greensInRegulation.fraction.map { $0 * 100 }, theirs: them.greensInRegulation.fraction.map { $0 * 100 }, format: { "\(Int($0.rounded()))%" })
            ComparisonBar(label: "Fairways", mine: me.fairways.fraction.map { $0 * 100 }, theirs: them.fairways.fraction.map { $0 * 100 }, format: { "\(Int($0.rounded()))%" })
            ComparisonBar(label: "Putts / hole", mine: me.puttsPerHole, theirs: them.puttsPerHole, format: { String(format: "%.2f", $0) }, lowerIsBetter: true)
            ComparisonBar(label: "Birdies or better", mine: Double(me.birdiesOrBetter), theirs: Double(them.birdiesOrBetter), format: { "\(Int($0))" })
            ComparisonBar(label: "Scrambling", mine: me.scrambling.fraction.map { $0 * 100 }, theirs: them.scrambling.fraction.map { $0 * 100 }, format: { "\(Int($0.rounded()))%" })
        }
        .cardStyle()
    }
}
