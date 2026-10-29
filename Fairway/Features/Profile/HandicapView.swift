import SwiftUI
import Charts
import GolfKit

/// Handicap for one game type: automatic (after N rounds) or manual, with the
/// differentials that make it up.
struct HandicapView: View {
    @Environment(AppModel.self) private var app
    let gameType: GameType

    private var settings: Binding<HandicapSettings> {
        let type = gameType
        return Binding(
            get: { app.profile.handicapSettings(for: type) },
            set: { newValue in app.update { $0.profile?.setHandicapSettings(newValue, for: type) } }
        )
    }

    var body: some View {
        let result = app.handicap(for: gameType)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(result)
                modeCard
                if result.history.count > 1 { trendChart(result) }
                differentials(result)
                explanation
            }
            .padding()
            .animation(.snappySpring, value: settings.wrappedValue)
        }
        .background(Theme.background)
        .navigationTitle("\(gameType.displayName) handicap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ result: HandicapResult) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress(result))
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.playful, value: progress(result))
                VStack(spacing: 0) {
                    Text(result.displayIndex)
                        .font(.rounded(36, weight: .heavy))
                        .contentTransition(.numericText(value: result.index ?? 0))
                    Text("INDEX").font(.caption2.weight(.heavy)).opacity(0.8)
                }
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 6) {
                switch result.source {
                case .manual:
                    Text("Manual index").font(.headline)
                    if let calculated = result.calculatedIndex {
                        Text("Calculated from your rounds: \(HandicapCalculator.format(calculated))").font(.caption).opacity(0.85)
                    }
                case .calculated:
                    Text(gameType.usesWorldHandicapSystem ? "World Handicap System" : "Casual index").font(.headline)
                    Text("From \(result.eligibleRounds) score\(result.eligibleRounds == 1 ? "" : "s")").font(.caption).opacity(0.85)
                case .notEstablished:
                    Text("Almost there").font(.headline)
                    Text("\(result.eligibleRounds) of \(result.roundsRequired) rounds played. Your index appears after \(result.roundsUntilEstablished) more.")
                        .font(.caption).opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.gradient(for: gameType), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func progress(_ result: HandicapResult) -> CGFloat {
        if result.index != nil { return 1 }
        return CGFloat(result.eligibleRounds) / CGFloat(max(1, result.roundsRequired))
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Mode", selection: settings.mode) {
                Text("Automatic").tag(HandicapMode.automatic)
                Text("Manual").tag(HandicapMode.manual)
            }
            .pickerStyle(.segmented)

            if settings.wrappedValue.mode == .automatic {
                Stepper(value: settings.roundsRequired, in: HandicapSettings.minimumRounds...HandicapSettings.maximumRounds) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generate after \(settings.wrappedValue.roundsRequired) rounds").font(.subheadline.weight(.semibold))
                        Text(gameType.usesWorldHandicapSystem ? "WHS needs at least 3 scores (54 holes)." : "More rounds give a steadier index.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            } else {
                ManualIndexEditor(index: Binding(
                    get: { settings.wrappedValue.manualIndex ?? 18 },
                    set: { settings.wrappedValue.manualIndex = HandicapCalculator.roundToTenth($0) }
                ))
                .transition(.opacity)
            }
        }
        .cardStyle()
    }

    private func trendChart(_ result: HandicapResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Index over time").font(.headline)
            Chart(result.history, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Index", point.index))
                    .foregroundStyle(Theme.fairway)
                    .interpolationMethod(.stepEnd)
                PointMark(x: .value("Date", point.date), y: .value("Index", point.index))
                    .foregroundStyle(Theme.fairway)
                    .symbolSize(24)
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .frame(height: 160)
            Text("Lower is better, so the chart rises as you improve.").font(.caption2).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func differentials(_ result: HandicapResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent scores", subtitle: result.differentials.isEmpty ? nil : "Highlighted scores count toward your index")
            if result.differentials.isEmpty {
                Text("Complete a \(gameType.displayName.lowercased()) round of at least nine holes to start building your index.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(result.differentials) { differential in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(differential.usedInIndex ? Theme.fairway : Color.secondary.opacity(0.3))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(differential.courseName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(detail(differential)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f", differential.value))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(differential.usedInIndex ? Theme.fairway : .primary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        Divider().padding(.leading, 34)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func detail(_ d: HandicapDifferential) -> String {
        var parts = [d.date.formatted(date: .abbreviated, time: .omitted), "\(d.adjustedGrossScore)"]
        if gameType.usesWorldHandicapSystem {
            parts.append(String(format: "%.1f/%d", d.courseRating, d.slopeRating))
        }
        if d.isNineHole { parts.append(d.roundIDs.count > 1 ? "2 × 9 holes" : "9 holes") }
        if d.isEstimatedRating { parts.append("est. rating") }
        return parts.joined(separator: " · ")
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How it's worked out").font(.headline)
            if gameType.usesWorldHandicapSystem {
                Text("Each round becomes a score differential: (113 ÷ slope) × (adjusted score − course rating). Holes are capped at net double bogey. Your index averages the best 8 of your last 20 differentials (fewer while you're getting started, with the official adjustments). Courses without a published rating use par and a slope of 113.")
            } else {
                Text("Pitch & putt and mini golf have no official ratings, so Fairway averages the best half of your last ten rounds' scores over par, scaled to 18 holes.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .cardStyle()
    }
}

/// Fine control for entering an index: slider plus ±0.1 buttons.
struct ManualIndexEditor: View {
    @Binding var index: Double

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { index = max(-10, index - 0.1) } label: { Image(systemName: "minus") }
                    .buttonStyle(CircleIconButtonStyle(size: 40))
                Spacer()
                Text(HandicapCalculator.format(index))
                    .font(.rounded(40, weight: .heavy))
                    .contentTransition(.numericText(value: index))
                    .animation(.snappySpring, value: index)
                Spacer()
                Button { index = min(54, index + 0.1) } label: { Image(systemName: "plus") }
                    .buttonStyle(CircleIconButtonStyle(size: 40))
            }
            Slider(value: $index, in: -10...54, step: 0.1)
            Text("Enter your official index. Plus handicaps are shown with a +.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
