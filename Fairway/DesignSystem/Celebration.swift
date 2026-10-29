import SwiftUI

/// A toast that drops in for a moment on birdies and personal bests.
struct CelebrationBanner: View {
    let title: String
    let subtitle: String
    var systemImage = "sparkles"

    var body: some View {
        ToastView(title: title, message: subtitle, systemImage: systemImage, iconColor: Theme.OnToast.celebration)
    }
}

/// The logo: a flag on a pin that waves gently.
struct FlagMark: View {
    var poleColor: Color = .primary
    var animated = true

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                let w = Double(size.width), h = Double(size.height)
                let poleX: Double = w * 0.32
                let poleWidth: Double = max(2, w * 0.035)
                let pole = Path(roundedRect: CGRect(x: poleX - poleWidth / 2, y: h * 0.06, width: poleWidth, height: h * 0.84), cornerRadius: poleWidth / 2)
                context.fill(pole, with: .color(poleColor))

                var flag = Path()
                let top: Double = h * 0.07
                let length: Double = w * 0.56
                let height: Double = h * 0.3
                let left = poleX + poleWidth / 2
                flag.move(to: CGPoint(x: left, y: top))
                let steps = 24
                for i in 0...steps {
                    let f = Double(i) / Double(steps)
                    let wave: Double = sin(f * 4.5 + t * 3) * 0.035 * h * f
                    flag.addLine(to: CGPoint(x: left + length * f, y: top + height * 0.5 * f + wave))
                }
                for i in stride(from: steps, through: 0, by: -1) {
                    let f = Double(i) / Double(steps)
                    let wave: Double = sin(f * 4.5 + t * 3) * 0.035 * h * f
                    flag.addLine(to: CGPoint(x: left + length * f, y: top + height - height * 0.5 * f + wave))
                }
                flag.closeSubpath()
                context.fill(flag, with: .color(Theme.flag))

                let cup = Path(ellipseIn: CGRect(x: poleX - w * 0.2, y: h * 0.88, width: w * 0.4, height: h * 0.07))
                context.fill(cup, with: .color(poleColor.opacity(0.18)))
            }
        }
        .accessibilityHidden(true)
    }
}
