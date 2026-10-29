import SwiftUI
import GolfKit

/// First launch: name, avatar, units (metric by default) and handicap.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app

    @State private var step = 0
    @State private var name = ""
    @State private var avatar = Avatar(emoji: "🏌️", colorIndex: 0)
    @State private var units: UnitSystem = .default
    @State private var handicapMode: HandicapMode = .automatic
    @State private var manualIndex = 18.0
    @State private var roundsRequired = 3
    @State private var loadSample = true
    @FocusState private var nameFocused: Bool

    private let steps = 4

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            FloatingBalls().ignoresSafeArea()

            VStack(spacing: 0) {
                ProgressDots(count: steps, current: step)
                    .padding(.top, 12)

                ZStack {
                    switch step {
                    case 0: welcome
                    case 1: identity
                    case 2: preferences
                    default: handicap
                    }
                }
                .frame(maxHeight: .infinity)
                .transition(.asymmetric(insertion: .push(from: .trailing), removal: .push(from: .leading)))
                .id(step)

                footer
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            FlagMark()
                .frame(width: 140, height: 160)
            Text("Fairway")
                .font(.rounded(52, weight: .heavy))
            Text("Track every shot, play friends with a four-letter code, run tournaments and watch your round replay on the map.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .opacity(0.9)
            HStack(spacing: 10) {
                ForEach(GameType.allCases) { type in
                    InfoPill(text: type.displayName, systemImage: type.symbolName, tint: .white)
                }
            }
            Spacer()
        }
    }

    private var identity: some View {
        VStack(spacing: 24) {
            Spacer()
            AvatarView(avatar: avatar, size: 110, showsRing: true)
                .shadow(radius: 12)
                .scaleEffect(name.isEmpty ? 1 : 1.05)
                .animation(.playful, value: avatar)
            Text("What should we call you?")
                .font(.title2.weight(.bold))
            TextField("", text: $name, prompt: Text("Your name").foregroundStyle(.white.opacity(0.6)))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($nameFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.words)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                ForEach(Avatar.emojiChoices, id: \.self) { emoji in
                    Button {
                        avatar.emoji = emoji
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(avatar.emoji == emoji ? 0.35 : 0.1), in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            HStack(spacing: 10) {
                ForEach(0..<Theme.avatarPalette.count, id: \.self) { index in
                    Circle()
                        .fill(Theme.avatarColor(index))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(.white, lineWidth: avatar.colorIndex == index ? 3 : 0))
                        .onTapGesture { avatar.colorIndex = index }
                }
            }
            Spacer()
        }
        .onAppear { nameFocused = true }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("Distances").font(.title2.weight(.bold))
            Text("Metric is the default. You can switch any time in Settings.")
                .opacity(0.85)
            HStack(spacing: 12) {
                ForEach(UnitSystem.allCases) { system in
                    Button {
                        units = system
                    } label: {
                        VStack(spacing: 6) {
                            Text(system == .metric ? "152 m" : "166 yd")
                                .font(.rounded(26, weight: .bold))
                            Text(system.displayName).font(.subheadline.weight(.semibold))
                            Text(system == .metric ? "metres · °C · km/h" : "yards · °F · mph")
                                .font(.caption).opacity(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.white.opacity(units == system ? 0.28 : 0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(units == system ? 0.9 : 0), lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .animation(.snappySpring, value: units)

            Toggle(isOn: $loadSample) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore with sample rounds").font(.headline)
                    Text("Adds a few months of demo rounds and matches so the stats screens have something to show. Remove them any time.")
                        .font(.caption).opacity(0.85)
                }
            }
            .tint(Theme.lime)
            .padding(16)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer()
        }
    }

    private var handicap: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Your handicap").font(.title2.weight(.bold))
            Picker("Handicap", selection: $handicapMode) {
                Text("Work it out for me").tag(HandicapMode.automatic)
                Text("I have one").tag(HandicapMode.manual)
            }
            .pickerStyle(.segmented)
            .environment(\.colorScheme, .dark)

            if handicapMode == .automatic {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Fairway calculates a World Handicap System index once you've played enough rounds.")
                        .opacity(0.9)
                    Stepper(value: $roundsRequired, in: HandicapSettings.minimumRounds...HandicapSettings.maximumRounds) {
                        Text("After \(roundsRequired) rounds").font(.headline)
                    }
                }
                .padding(16)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                VStack(spacing: 8) {
                    Text(HandicapCalculator.format(manualIndex))
                        .font(.rounded(64, weight: .heavy))
                        .contentTransition(.numericText(value: manualIndex))
                        .animation(.snappySpring, value: manualIndex)
                    Slider(value: $manualIndex, in: -5...54, step: 0.1)
                        .tint(Theme.lime)
                    Text("Drag to set your index · plus handicaps shown with +")
                        .font(.caption).opacity(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.snappySpring, value: handicapMode)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation(.snappySpring) { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 54, height: 54)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(PressableStyle())
                .transition(.scale.combined(with: .opacity))
            }
            Button {
                advance()
            } label: {
                Text(step == steps - 1 ? "Tee off" : "Continue")
                    .font(.headline)
                    .foregroundStyle(Theme.deepGreen)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(step == 1 && name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(step == 1 && name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)
        }
        .animation(.snappySpring, value: step)
        .sensoryFeedback(.selection, trigger: step)
    }

    private func advance() {
        guard step == steps - 1 else {
            nameFocused = false
            withAnimation(.snappySpring) { step += 1 }
            return
        }
        let settings = HandicapSettings(
            mode: handicapMode,
            manualIndex: handicapMode == .manual ? HandicapCalculator.roundToTenth(manualIndex) : nil,
            roundsRequired: roundsRequired
        )
        let profile = PlayerProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            avatar: avatar,
            handicap: settings
        )
        app.update {
            $0.profile = profile
            $0.settings.units = units
        }
        if loadSample { app.loadSampleData() }
        app.location.requestAccess()
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index <= current ? 1 : 0.35))
                    .frame(width: index == current ? 26 : 8, height: 8)
            }
        }
        .animation(.snappySpring, value: current)
    }
}

/// The logo: a flag that waves gently.
struct FlagMark: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let w = Double(size.width), h = Double(size.height)
                let poleX: Double = w * 0.35
                let pole = Path(roundedRect: CGRect(x: poleX - 3, y: h * 0.05, width: 6, height: h * 0.85), cornerRadius: 3)
                context.fill(pole, with: .color(.white))

                var flag = Path()
                let top: Double = h * 0.07
                let length: Double = w * 0.55
                let height: Double = h * 0.32
                flag.move(to: CGPoint(x: poleX + 3, y: top))
                let steps = 24
                for i in 0...steps {
                    let f = Double(i) / Double(steps)
                    let wave: Double = sin(f * 5 + t * 4) * 6 * f
                    flag.addLine(to: CGPoint(x: poleX + 3 + length * f, y: top + height * 0.5 * f + wave))
                }
                for i in stride(from: steps, through: 0, by: -1) {
                    let f = Double(i) / Double(steps)
                    let wave: Double = sin(f * 5 + t * 4) * 6 * f
                    flag.addLine(to: CGPoint(x: poleX + 3 + length * f, y: top + height - height * 0.5 * f + wave))
                }
                flag.closeSubpath()
                context.fill(flag, with: .color(Theme.flag))

                let hole = Path(ellipseIn: CGRect(x: poleX - 28, y: h * 0.86, width: 56, height: 14))
                context.fill(hole, with: .color(.black.opacity(0.35)))
            }
        }
    }
}

/// Soft golf balls drifting in the background.
struct FloatingBalls: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for i in 0..<9 {
                    let seed = Double(i) * 1.7
                    let x = (sin(seed * 3.1 + t * 0.07) * 0.5 + 0.5) * Double(size.width)
                    let y = (cos(seed * 2.3 + t * 0.05) * 0.5 + 0.5) * Double(size.height)
                    let r = 18 + (sin(seed) * 0.5 + 0.5) * 36
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.06)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
