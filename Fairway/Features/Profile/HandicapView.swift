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
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                hero(result).reveal(0)
                modeSection.reveal(1)
                if result.history.count > 1 { trendChart(result) }
                differentials(result)
                explanation
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
            .animation(.snappySpring, value: settings.wrappedValue)
        }
        .background(Theme.background)
        .navigationTitle("\(gameType.displayName) handicap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ result: HandicapResult) -> some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                Circle().stroke(Theme.fill, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress(result))
                    .stroke(Theme.fairway, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.0).delay(0.2), value: progress(result))
                VStack(spacing: 0) {
                    Text(result.displayIndex)
                        .font(.display(40, weight: .regular))
                        .foregroundStyle(result.isEnabled ? .primary : .secondary)
                        .contentTransition(.numericText(value: result.index ?? 0))
                    Eyebrow(result.isEnabled ? "Index" : "Handicap")
                }
            }
            .frame(width: 136, height: 136)

            VStack(alignment: .leading, spacing: 6) {
                switch result.source {
                case .manual:
                    Text("Manual index").font(.headline)
                    if let calculated = result.calculatedIndex {
                        Text("Calculated from your rounds: \(HandicapCalculator.format(calculated))").font(.footnote).foregroundStyle(.secondary)
                    }
                case .calculated:
                    Text(gameType.usesWorldHandicapSystem ? "World Handicap System" : "Casual index").font(.headline)
                    Text("From \(result.eligibleRounds) score\(result.eligibleRounds == 1 ? "" : "s")").font(.footnote).foregroundStyle(.secondary)
                case .notEstablished:
                    Text("Almost there").font(.headline)
                    Text("\(result.eligibleRounds) of \(result.roundsRequired) rounds played. Your index appears after \(result.roundsUntilEstablished) more.")
                        .font(.footnote).foregroundStyle(.secondary)
                case .off:
                    Text("Handicap off").font(.headline)
                    Text("You play off scratch in net games. Rounds still count, so your index is ready whenever you switch it back on.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 12)
    }

    private func progress(_ result: HandicapResult) -> CGFloat {
        if !result.isEnabled { return 0 }
        if result.index != nil { return 1 }
        return CGFloat(result.eligibleRounds) / CGFloat(max(1, result.roundsRequired))
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "How it's set")
            Toggle(isOn: settings.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use a handicap").font(.body.weight(.medium))
                    Text(settings.wrappedValue.isEnabled
                         ? "Shown on your profile and used for strokes in net matches and tournaments."
                         : "Off: no index is shown and you play off scratch.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }
            .tint(Theme.fairway)
            .sensoryFeedback(.selection, trigger: settings.wrappedValue.isEnabled)

            if settings.wrappedValue.isEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Mode", selection: settings.mode) {
                        Text("Automatic").tag(HandicapMode.automatic)
                        Text("Manual").tag(HandicapMode.manual)
                    }
                    .pickerStyle(.segmented)

                    if settings.wrappedValue.mode == .automatic {
                        Stepper(value: settings.roundsRequired, in: HandicapSettings.minimumRounds...HandicapSettings.maximumRounds) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Generate after \(settings.wrappedValue.roundsRequired) rounds").font(.body.weight(.medium))
                                Text(gameType.usesWorldHandicapSystem ? "WHS needs at least 3 scores (54 holes)." : "More rounds give a steadier index.")
                                    .font(.footnote).foregroundStyle(.secondary)
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func trendChart(_ result: HandicapResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Index over time", subtitle: "Lower is better, so the line rises as you improve")
            Chart(result.history, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Index", point.index))
                    .foregroundStyle(Theme.fairway)
                    .lineStyle(StrokeStyle(lineWidth: 1.75))
                    .interpolationMethod(.stepEnd)
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .frame(height: 160)
        }
    }

    private func differentials(_ result: HandicapResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Recent scores", subtitle: result.differentials.isEmpty ? nil : "Green scores count toward your index")
            if result.differentials.isEmpty {
                Text("Complete a \(gameType.displayName.lowercased()) round of at least nine holes to start building your index.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                DividedList(result.differentials, inset: 20) { differential in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(differential.usedInIndex ? Theme.fairway : Theme.fill)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(differential.courseName).font(.body.weight(.medium)).lineLimit(1)
                            Text(detail(differential)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f", differential.value))
                            .font(.figure(17, weight: differential.usedInIndex ? .semibold : .regular))
                            .foregroundStyle(differential.usedInIndex ? Theme.fairway : .primary)
                    }
                    .padding(.vertical, 10)
                }
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
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "How it's worked out")
            Group {
                if gameType.usesWorldHandicapSystem {
                    Text("Each round becomes a score differential: (113 ÷ slope) × (adjusted score − course rating). Holes are capped at net double bogey. Your index averages the best 8 of your last 20 differentials (fewer while you're getting started, with the official adjustments). Courses without a published rating use par and a slope of 113.")
                } else {
                    Text("Pitch & putt and mini golf have no official ratings, so Fairway averages the best half of your last ten rounds' scores over par, scaled to 18 holes.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
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
                    .font(.display(44, weight: .regular))
                    .contentTransition(.numericText(value: index))
                    .animation(.snappySpring, value: index)
                Spacer()
                Button { index = min(54, index + 0.1) } label: { Image(systemName: "plus") }
                    .buttonStyle(CircleIconButtonStyle(size: 40))
            }
            Slider(value: $index, in: -10...54, step: 0.1)
                .tint(Theme.fairway)
            Text("Enter your official index. Plus handicaps are shown with a +.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
