import SwiftUI
import GolfKit

// MARK: - Cards

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Buttons

/// Big pill button with a gradient fill and a springy press.
struct PrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.heroGradient
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(gradient.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .shadow(color: Theme.deepGreen.opacity(isEnabled ? 0.25 : 0), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappySpring, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.fairway

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.12), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappySpring, value: configuration.isPressed)
    }
}

/// Subtle scale-down on press for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappySpring, value: configuration.isPressed)
    }
}

/// Round +/- buttons used by steppers.
struct CircleIconButtonStyle: ButtonStyle {
    var tint: Color = Theme.fairway
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.snappySpring, value: configuration.isPressed)
    }
}

// MARK: - Chips

struct Chip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool
    var tint: Color = Theme.fairway
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : .primary)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)))
            }
        }
        .buttonStyle(PressableStyle())
        .animation(.snappySpring, value: isSelected)
    }
}

struct InfoPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Stats

struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String?
    var systemImage: String?
    var tint: Color = Theme.fairway

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.rounded(26, weight: .bold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Horizontal comparison bar: you vs a friend.
struct ComparisonBar: View {
    let label: String
    let mine: Double?
    let theirs: Double?
    let format: (Double) -> String
    /// When true, the lower value is better (strokes, putts).
    var lowerIsBetter = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(mine.map(format) ?? "—").font(.subheadline.weight(.bold)).foregroundStyle(winnerColor(isMine: true))
                Spacer()
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(theirs.map(format) ?? "—").font(.subheadline.weight(.bold)).foregroundStyle(winnerColor(isMine: false))
            }
            GeometryReader { geo in
                let total = max(0.0001, (mine ?? 0) + (theirs ?? 0))
                let share = (mine ?? 0) / total
                HStack(spacing: 3) {
                    Capsule().fill(Theme.fairway).frame(width: max(4, geo.size.width * share - 1.5))
                    Capsule().fill(Theme.water.opacity(0.75))
                }
            }
            .frame(height: 8)
        }
    }

    private func winnerColor(isMine: Bool) -> Color {
        guard let mine, let theirs, mine != theirs else { return .primary }
        let mineBetter = lowerIsBetter ? mine < theirs : mine > theirs
        return mineBetter == isMine ? (isMine ? Theme.fairway : Theme.water) : .primary
    }
}

// MARK: - Avatars

struct AvatarView: View {
    let avatar: Avatar
    var size: CGFloat = 44
    var showsRing = false

    var body: some View {
        Text(avatar.emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(Theme.avatarColor(avatar.colorIndex).gradient, in: Circle())
            .overlay {
                if showsRing {
                    Circle().strokeBorder(.white, lineWidth: max(2, size / 18))
                }
            }
    }
}

// MARK: - Scores

/// Scorecard notation: circles for under par, squares for over par.
struct ScoreBadge: View {
    let strokes: Int?
    let par: Int
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            if let strokes {
                let diff = strokes - par
                shape(diff: diff)
                Text("\(strokes)")
                    .font(.rounded(size * 0.5, weight: .bold))
                    .foregroundStyle(diff < 0 ? .white : .primary)
                    .contentTransition(.numericText(value: Double(strokes)))
            } else {
                Text("–").foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func shape(diff: Int) -> some View {
        let inset = size * 0.12
        switch diff {
        case ..<(-1):
            Circle().fill(Theme.gold)
                .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1.5).padding(-inset * 0.6))
        case -1:
            Circle().fill(Theme.flag)
        case 0:
            Color.clear
        case 1:
            RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.water, lineWidth: 1.5)
        default:
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color(hex: 0x5E5CE6), lineWidth: 1.5)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x5E5CE6), lineWidth: 1.2).padding(inset))
        }
    }
}

/// "+3", "E", "-1" with scorecard colours.
struct ToParText: View {
    let toPar: Int
    var font: Font = .headline

    var body: some View {
        Text(Leaderboard.formatToPar(toPar))
            .font(font)
            .foregroundStyle(toPar < 0 ? Theme.flag : (toPar == 0 ? .primary : .secondary))
            .contentTransition(.numericText(value: Double(toPar)))
            .monospacedDigit()
    }
}

// MARK: - Empty states and loading

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "flag"
    var actionTitle: String?
    var action: (() -> Void)?
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.fairway.gradient)
                .symbolEffect(.bounce, value: appeared)
                .onAppear { appeared = true }
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 240)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

/// Sweeping highlight for loading placeholders.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

struct LoadingCard: View {
    var height: CGFloat = 120

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(height: height)
            .shimmering()
    }
}

/// Pulsing red dot for anything live.
struct LiveBadge: View {
    var text = "LIVE"

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.flag)
                .frame(width: 8, height: 8)
                .phaseAnimator([false, true]) { dot, glowing in
                    dot
                        .scaleEffect(glowing ? 1.25 : 0.85)
                        .opacity(glowing ? 1 : 0.5)
                } animation: { _ in .easeInOut(duration: 0.8) }
            Text(text).font(.caption2.weight(.heavy)).tracking(1)
        }
        .foregroundStyle(Theme.flag)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.flag.opacity(0.12), in: Capsule())
    }
}

// MARK: - Join codes

/// Jackbox-style big letter tiles that pop in one after another.
struct CodeTiles: View {
    let code: String
    var tileSize: CGFloat = 64
    @State private var revealed = false

    var body: some View {
        HStack(spacing: tileSize * 0.16) {
            ForEach(Array(code.enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(.rounded(tileSize * 0.58, weight: .heavy))
                    .foregroundStyle(Theme.deepGreen)
                    .frame(width: tileSize, height: tileSize * 1.15)
                    .background(.white, in: RoundedRectangle(cornerRadius: tileSize * 0.22, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                    .rotationEffect(.degrees(revealed ? (index.isMultiple(of: 2) ? -3 : 3) : 0))
                    .scaleEffect(revealed ? 1 : 0.3)
                    .opacity(revealed ? 1 : 0)
                    .animation(.playful.delay(Double(index) * 0.08), value: revealed)
            }
        }
        .onAppear { revealed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Join code \(JoinCode.spaced(code))")
    }
}
