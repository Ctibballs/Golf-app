import SwiftUI
import GolfKit

/// Jackbox-style join screen: four big letter boxes and a keypad of only valid letters.
struct JoinGameView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isJoining = false
    @State private var shake = 0
    @State private var errorText: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Eyebrow("Join a game")
                    Text("Enter the room code")
                        .font(.display(28))
                    Text("Ask the host for the four letters on their screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 12)

                codeBoxes
                    .modifier(ShakeEffect(shakes: CGFloat(shake)))
                    .animation(.default, value: shake)

                if let errorText {
                    Text(errorText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.flag)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .scale))
                }

                Spacer(minLength: 0)
                keypad
            }
            .padding()
            .background(Theme.background)
            .animation(.snappySpring, value: errorText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first {
                            Task { @MainActor in enter(JoinCode.normalize(first)) }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
            }
            .sensoryFeedback(.error, trigger: shake)
            .sensoryFeedback(.selection, trigger: code)
        }
    }

    private var codeBoxes: some View {
        HStack(spacing: 12) {
            ForEach(0..<JoinCode.length, id: \.self) { index in
                let letter = index < code.count ? String(Array(code)[index]) : ""
                let isNext = index == code.count
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isNext ? Theme.fairway : Theme.outline, lineWidth: isNext ? 1.5 : 1)
                    Text(letter)
                        .font(.system(size: 40, weight: .semibold, design: .monospaced))
                        .scaleEffect(letter.isEmpty ? 0.6 : 1)
                        .opacity(letter.isEmpty ? 0 : 1)
                    if isNext && !isJoining {
                        Rectangle()
                            .fill(Theme.fairway)
                            .frame(width: 2, height: 30)
                            .phaseAnimator([1.0, 0.0]) { caret, opacity in
                                caret.opacity(opacity)
                            } animation: { _ in .easeInOut(duration: 0.55) }
                    }
                }
                .frame(width: 64, height: 78)
                .animation(.snappySpring, value: letter)
                .animation(.easeOut(duration: 0.2), value: isNext)
            }
        }
        .overlay {
            if isJoining {
                ProgressView().controlSize(.large).padding().background(.regularMaterial, in: Circle())
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(JoinCode.alphabet, id: \.self) { letter in
                    Button {
                        enter(String(letter))
                    } label: {
                        Text(String(letter))
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.primary)
                    .disabled(isJoining)
                }
            }
            Button {
                if !code.isEmpty { code.removeLast() }
                errorText = nil
            } label: {
                Label("Delete", systemImage: "delete.left")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(.primary)
        }
    }

    private func enter(_ text: String) {
        errorText = nil
        let combined = JoinCode.normalize(code + text)
        code = combined
        if JoinCode.isValid(code) {
            Task { await join() }
        }
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        do {
            let result = try await app.join(code: code)
            dismiss()
            switch result {
            case .match(let session):
                app.present(.match(session.id), afterDismissing: true)
            case .tournament(let session):
                app.present(.tournament(session.id), afterDismissing: true)
            }
        } catch {
            errorText = error.localizedDescription
            shake += 1
            withAnimation(.snappySpring.delay(0.3)) { code = "" }
        }
    }
}

/// Horizontal wobble for wrong codes.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 12 * sin(shakes * .pi * 4), y: 0))
    }
}
