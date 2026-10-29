import SwiftUI
import GolfKit

// MARK: - Type

/// Small uppercase label that sits above a value or a block of content.
struct Eyebrow: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.eyebrow)
            .tracking(1.1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - Sections

/// A hairline rule with a label: the house way to start a section.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    let accessory: Accessory

    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(title)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                accessory
            }
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension SectionHeader where Accessory == SectionAction {
    init(title: String, subtitle: String? = nil, actionTitle: String?, action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle) { SectionAction(title: actionTitle, action: action) }
    }
}

/// The text button on the right of a section header.
struct SectionAction: View {
    let title: String?
    let action: () -> Void

    var body: some View {
        if let title {
            Button(title, action: action)
                .font(.subheadline.weight(.medium))
                .tint(Theme.fairway)
        }
    }
}

/// Rows separated by hairlines, with no box around them.
struct DividedList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    var inset: CGFloat = 0
    let row: (Data.Element) -> Row

    init(_ data: Data, inset: CGFloat = 0, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.inset = inset
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                row(element)
                if index < data.count - 1 {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, inset)
                }
            }
        }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }
}

/// A navigation-style row: optional icon, title, detail and a chevron.
struct NavigationRowLabel: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var value: String?

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Theme.fairway)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// One choice in a list of mutually exclusive options.
struct RadioRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(isSelected ? Theme.fairway : .secondary)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.fairway : Color.secondary.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - Metrics

struct MetricItem: Identifiable {
    let label: String
    let value: String
    var detail: String?
    var tint: Color?
    var id: String { label }
}

/// Figures laid out in columns, split by hairlines like a printed table.
struct MetricGrid: View {
    let items: [MetricItem]
    var columns = 2
    var compact = false

    private var rows: [[MetricItem]] {
        stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        Group {
                            if column < row.count {
                                MetricCell(item: row[column], compact: compact)
                            } else {
                                Color.clear
                            }
                        }
                        .padding(.leading, column == 0 ? 0 : 14)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if column < columns - 1 {
                            Rectangle().fill(Theme.hairline).frame(width: 0.5)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if rowIndex < rows.count - 1 { Hairline() }
            }
        }
    }
}

struct MetricCell: View {
    let item: MetricItem
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            Eyebrow(item.label)
            Text(item.value)
                .font(compact ? Font.figure(17, weight: .semibold) : Font.figure(26, weight: .medium))
                .foregroundStyle(item.tint ?? .primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail = item.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, compact ? 10 : 14)
    }
}

/// A thin bar that grows to its value when it first appears.
struct ProgressLine: View {
    let fraction: Double
    var tint: Color = Theme.fairway
    var height: CGFloat = 3
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(shown ? min(1, max(0, fraction)) : 0))
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.15)) { shown = true } }
    }
}

/// You vs a friend on one stat: values either side of the label and a split bar.
struct ComparisonBar: View {
    let label: String
    let mine: Double?
    let theirs: Double?
    let format: (Double) -> String
    /// When true, the lower value is better (strokes, putts).
    var lowerIsBetter = false
    @State private var shown = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(mine.map(format) ?? "—")
                    .font(.figure(17, weight: isBetter(mine: true) ? .semibold : .regular))
                    .foregroundStyle(isBetter(mine: true) ? Theme.fairway : .primary)
                Spacer()
                Text(label).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(theirs.map(format) ?? "—")
                    .font(.figure(17, weight: isBetter(mine: false) ? .semibold : .regular))
                    .foregroundStyle(isBetter(mine: false) ? Theme.water : .primary)
            }
            GeometryReader { geo in
                let total = max(0.0001, abs(mine ?? 0) + abs(theirs ?? 0))
                let share = shown ? abs(mine ?? 0) / total : 0.5
                HStack(spacing: 2) {
                    Rectangle().fill(Theme.fairway).frame(width: max(2, geo.size.width * share - 1))
                    Rectangle().fill(Theme.water.opacity(0.55))
                }
            }
            .frame(height: 3)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.2)) { shown = true } }
    }

    private func isBetter(mine isMine: Bool) -> Bool {
        guard let mine, let theirs, mine != theirs else { return false }
        let mineBetter = lowerIsBetter ? mine < theirs : mine > theirs
        return mineBetter == isMine
    }
}

// MARK: - Buttons

/// Solid accent button, full width.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.fairway
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(tint.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var height: CGFloat = 50
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(configuration.isPressed ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.outline, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Dims on press, for rows and anything that isn't shaped like a button.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outlined round icon button, used for steppers and toolbars.
struct CircleIconButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var size: CGFloat = 44
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(configuration.isPressed ? Theme.fill : .clear, in: Circle())
            .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.snappySpring, value: configuration.isPressed)
    }
}

// MARK: - Choices

/// A filter or option token: outlined, filled with ink when selected.
struct Chip: View {
    let title: String
    var systemImage: String?
    /// A small colour swatch shown before the title (tee colours).
    var swatch: Color?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5))
                }
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Theme.background : Color.primary)
            .background(isSelected ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isSelected ? Color.clear : Theme.outline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }
}

/// Text tabs with an underline that slides to the selection.
struct UnderlineTabs<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 26) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.snappySpring) { selection = option }
                } label: {
                    VStack(spacing: 9) {
                        Text(title(option))
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                        ZStack {
                            if selected {
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            } else {
                                Color.clear.frame(height: 2)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selected)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// An inline label: icon and text in a muted colour, no background.
struct InfoPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(tint)
    }
}

/// A text field drawn as a label above an underline.
struct UnderlineField: View {
    let title: String
    @Binding var text: String
    var prompt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(title)
            TextField(title, text: $text, prompt: prompt.map { Text($0) })
                .font(.title3)
                .padding(.vertical, 6)
            Hairline()
        }
    }
}

// MARK: - Avatars

struct AvatarView: View {
    let avatar: Avatar
    var size: CGFloat = 44
    var showsRing = false

    var body: some View {
        let tint = Theme.avatarColor(avatar.colorIndex)
        Text(avatar.emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background {
                Circle().fill(Theme.background)
                Circle().fill(tint.opacity(0.16))
            }
            .overlay {
                Circle().strokeBorder(showsRing ? Theme.fairway : tint.opacity(0.35), lineWidth: showsRing ? max(1.5, size / 22) : 0.75)
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
                    .font(.figure(size * 0.46, weight: .semibold))
                    .foregroundStyle(diff < 0 ? .white : Theme.scoreColor(toPar: diff))
                    .contentTransition(.numericText(value: Double(strokes)))
            } else {
                Text("–").font(.figure(size * 0.4)).foregroundStyle(.tertiary)
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
                .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1).padding(-inset * 0.7))
        case -1:
            Circle().fill(Theme.flag)
        case 0:
            Color.clear
        case 1:
            Rectangle().strokeBorder(Theme.water, lineWidth: 1.25)
        default:
            Rectangle().strokeBorder(Theme.double, lineWidth: 1.25)
                .overlay(Rectangle().strokeBorder(Theme.double, lineWidth: 1).padding(inset))
        }
    }
}

/// "+3", "E", "-1", red when under par.
struct ToParText: View {
    let toPar: Int
    var font: Font = .headline

    var body: some View {
        Text(Leaderboard.formatToPar(toPar))
            .font(font)
            .foregroundStyle(toPar < 0 ? Theme.flag : .primary)
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
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: appeared)
                .padding(.bottom, 4)
                .onAppear { appeared = true }
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.fairway, height: 44))
                    .frame(maxWidth: 240)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 12)
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
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Placeholder lines shaped like list rows.
struct SkeletonRows: View {
    var count = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.fill).frame(width: 190, height: 13)
                    RoundedRectangle(cornerRadius: 4).fill(Theme.fill).frame(width: 120, height: 10)
                }
                .padding(.vertical, 16)
                if index < count - 1 { Hairline() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(width: 7, height: 7)
                .phaseAnimator([false, true]) { dot, glowing in
                    dot
                        .scaleEffect(glowing ? 1.2 : 0.8)
                        .opacity(glowing ? 1 : 0.45)
                } animation: { _ in .easeInOut(duration: 0.9) }
            Text(text).font(.eyebrow).tracking(1.1)
        }
        .foregroundStyle(Theme.flag)
    }
}

// MARK: - Join codes

/// The four-letter room code in outlined boxes; letters rise in one after another.
struct CodeTiles: View {
    let code: String
    var tileSize: CGFloat = 56
    @State private var revealed = false

    var body: some View {
        HStack(spacing: tileSize * 0.14) {
            ForEach(Array(code.enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(.system(size: tileSize * 0.52, weight: .semibold, design: .monospaced))
                    .frame(width: tileSize, height: tileSize * 1.18)
                    .overlay(RoundedRectangle(cornerRadius: tileSize * 0.16, style: .continuous).strokeBorder(Theme.outline, lineWidth: 1))
                    .offset(y: revealed ? 0 : 10)
                    .opacity(revealed ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.1 + Double(index) * 0.07), value: revealed)
            }
        }
        .onAppear { revealed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Join code \(JoinCode.spaced(code))")
    }
}

// MARK: - Motion

/// Fades content up into place the first time it appears.
struct Reveal: ViewModifier {
    var delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(.gentle.delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Staggered entrance: pass the item's order on the page.
    func reveal(_ order: Int = 0) -> some View {
        modifier(Reveal(delay: Double(order) * 0.06))
    }

    /// A ring that ripples out from the view each time `trigger` changes.
    func pulseRing(trigger: Int, color: Color = Theme.flag) -> some View {
        background {
            Circle()
                .stroke(color, lineWidth: 1.5)
                .phaseAnimator([0, 1, 2], trigger: trigger) { ring, phase in
                    ring
                        .scaleEffect(phase == 2 ? 1.9 : 1)
                        .opacity(phase == 1 ? 0.9 : 0)
                } animation: { phase in
                    phase == 2 ? .easeOut(duration: 0.7) : .linear(duration: 0.01)
                }
        }
    }

    /// Lists and forms in the house style: plain rows on the page background.
    func flatList() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

/// A small line chart shape. Lower values (better handicaps) are drawn higher.
struct Sparkline: Shape {
    let values: [Double]
    var invert = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return path }
        let span = max(0.0001, hi - lo)
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let normalized = CGFloat((v - lo) / span)
            let y = invert ? rect.minY + rect.height * normalized : rect.maxY - rect.height * normalized
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

/// A sparkline that draws itself in from the left.
struct AnimatedSparkline: View {
    let values: [Double]
    var color: Color = Theme.fairway
    @State private var progress: CGFloat = 0

    var body: some View {
        Sparkline(values: values)
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).delay(0.25)) { progress = 1 }
            }
    }
}

/// A floating message: a dark bar that drops in from the top.
struct ToastView: View {
    let title: String
    var message: String?
    var systemImage: String
    var iconColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconColor)
                .symbolEffect(.bounce, value: title)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let message {
                    Text(message).font(.footnote).opacity(0.75).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.onToast)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.toast, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal)
    }
}
