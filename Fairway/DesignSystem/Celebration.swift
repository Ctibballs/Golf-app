import SwiftUI

/// A short confetti burst for birdies, personal bests and wins. Drawn with Canvas so it
/// stays cheap even with lots of pieces.
struct ConfettiView: View {
    let trigger: Int
    var pieces = 70

    @State private var startDate: Date?
    private let duration: TimeInterval = 2.4
    private static let colors: [Color] = [Theme.flag, Theme.gold, Theme.lime, Theme.water, .white, Theme.fairway]

    var body: some View {
        TimelineView(.animation(paused: startDate == nil)) { timeline in
            Canvas { context, size in
                guard let start = startDate else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                for i in 0..<pieces {
                    var rng = SeededRandom(seed: UInt64(i + 1) &* 2654435761 &+ UInt64(trigger))
                    let originX: Double = Double(size.width) * (0.2 + 0.6 * rng.next())
                    let velocityX: Double = (rng.next() - 0.5) * 420
                    let velocityY: Double = -(380 + rng.next() * 420)
                    let gravity: Double = 900
                    let x: Double = originX + velocityX * t
                    let y: Double = Double(size.height) * 0.45 + velocityY * t + 0.5 * gravity * t * t
                    let spin = Angle.degrees(rng.next() * 360 + t * 540 * (rng.next() > 0.5 ? 1 : -1))
                    let fade: Double = max(0, 1 - t / duration)
                    let w: Double = 6 + rng.next() * 6
                    let h: Double = 4 + rng.next() * 8

                    context.opacity = fade
                    context.translateBy(x: x, y: y)
                    context.rotate(by: spin)
                    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                    let color = Self.colors[Int(rng.next() * Double(Self.colors.count)) % Self.colors.count]
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                    context.rotate(by: -spin)
                    context.translateBy(x: -x, y: -y)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            startDate = Date()
        }
    }
}

/// Tiny deterministic generator so each confetti piece keeps its path between frames.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}

/// A banner that drops in from the top for a moment ("Birdie!").
struct CelebrationBanner: View {
    let title: String
    let subtitle: String
    var systemImage = "sparkles"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.gold)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .padding(.horizontal)
    }
}
