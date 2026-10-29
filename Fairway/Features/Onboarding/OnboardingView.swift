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
        VStack(spacing: 0) {
            StepBar(count: steps, current: step)
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
        .background(Theme.background)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            FlagMark()
                .frame(width: 64, height: 78)
                .reveal(0)
            VStack(alignment: .leading, spacing: 10) {
                Text("Fairway")
                    .font(.display(54))
                Text("Your round, measured. Play friends with a four-letter code, run tournaments and watch every shot replay on the map.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .reveal(1)
            VStack(alignment: .leading, spacing: 0) {
                feature("location", "GPS shot tracking", "Distances to the green and every shot measured")
                Hairline().padding(.leading, 40)
                feature("person.2", "Matches and tournaments", "Friends join with a code, like a party game")
                Hairline().padding(.leading, 40)
                feature("chart.xyaxis.line", "Stats and handicap", "Per course, per hole and head to head")
            }
            .overlay(alignment: .top) { Hairline() }
            .padding(.top, 8)
            .reveal(2)
            Spacer()
        }
    }

    private func feature(_ systemImage: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Theme.fairway)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("What should we call you?")
                .font(.display(30))
            HStack(spacing: 16) {
                AvatarView(avatar: avatar, size: 72)
                    .animation(.snappySpring, value: avatar)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("", text: $name, prompt: Text("Your name"))
                        .font(.title2)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                    Hairline()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Avatar")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                    ForEach(Avatar.emojiChoices, id: \.self) { emoji in
                        Button {
                            avatar.emoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 38, height: 38)
                                .overlay(Circle().strokeBorder(avatar.emoji == emoji ? Theme.fairway : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                HStack(spacing: 10) {
                    ForEach(0..<Theme.avatarPalette.count, id: \.self) { index in
                        Circle()
                            .fill(Theme.avatarColor(index))
                            .frame(width: 24, height: 24)
                            .padding(3)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: avatar.colorIndex == index ? 1.5 : 0))
                            .onTapGesture { avatar.colorIndex = index }
                    }
                }
            }
            .padding(.top, 6)
            Spacer()
        }
        .onAppear { nameFocused = true }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("Distances").font(.display(30))
                Text("Metric is the default. You can switch any time in Settings.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(UnitSystem.allCases) { system in
                    let selected = units == system
                    Button {
                        units = system
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(system.displayName).font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? Theme.fairway : Color.secondary.opacity(0.5))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            Text(system == .metric ? "152 m" : "166 yd")
                                .font(.display(30, weight: .regular))
                            Text(system == .metric ? "Metres · °C · km/h" : "Yards · °F · mph")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                .strokeBorder(selected ? Theme.fairway : Theme.outline, lineWidth: selected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .sensoryFeedback(.selection, trigger: selected)
                }
            }
            .animation(.easeOut(duration: 0.2), value: units)

            Toggle(isOn: $loadSample) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore with sample rounds").font(.body.weight(.medium))
                    Text("Adds a few months of demo rounds and matches so the stats screens have something to show. Remove them any time.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.fairway)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
            Spacer()
        }
    }

    private var handicap: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Your handicap").font(.display(30))
            Picker("Handicap", selection: $handicapMode) {
                Text("Work it out for me").tag(HandicapMode.automatic)
                Text("I have one").tag(HandicapMode.manual)
            }
            .pickerStyle(.segmented)

            if handicapMode == .automatic {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Fairway calculates a World Handicap System index once you've played enough rounds.")
                        .foregroundStyle(.secondary)
                    Stepper(value: $roundsRequired, in: HandicapSettings.minimumRounds...HandicapSettings.maximumRounds) {
                        Text("After \(roundsRequired) rounds").font(.body.weight(.medium)).monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Hairline() }
                    .overlay(alignment: .bottom) { Hairline() }
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(HandicapCalculator.format(manualIndex))
                        .font(.display(72, weight: .regular))
                        .contentTransition(.numericText(value: manualIndex))
                        .animation(.snappySpring, value: manualIndex)
                    Slider(value: $manualIndex, in: -5...54, step: 0.1)
                        .tint(Theme.fairway)
                    Text("Drag to set your index. Plus handicaps are shown with a +.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .transition(.opacity)
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
                }
                .buttonStyle(CircleIconButtonStyle(size: 52))
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            Button {
                advance()
            } label: {
                HStack {
                    Text(step == steps - 1 ? "Tee off" : "Continue")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(step == 1 && name.trimmingCharacters(in: .whitespaces).isEmpty)
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

/// Thin segments that fill in as you move through onboarding.
private struct StepBar: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.primary : Theme.fill)
                    .frame(height: 3)
            }
        }
        .animation(.easeOut(duration: 0.3), value: current)
    }
}
