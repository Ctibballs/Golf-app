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
                    Text("Enter room code")
                        .font(.rounded(28, weight: .heavy))
                    Text("Ask the host for the four letters on their screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(letter.isEmpty ? Theme.card : Color.white)
                        .shadow(color: .black.opacity(letter.isEmpty ? 0.04 : 0.15), radius: 8, y: 4)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(index == code.count ? Theme.fairway : .clear, lineWidth: 3)
                    Text(letter)
                        .font(.rounded(44, weight: .heavy))
                        .foregroundStyle(Theme.deepGreen)
                        .scaleEffect(letter.isEmpty ? 0.3 : 1)
                        .opacity(letter.isEmpty ? 0 : 1)
                }
                .frame(width: 66, height: 80)
                .rotationEffect(.degrees(letter.isEmpty ? 0 : (index.isMultiple(of: 2) ? -3 : 3)))
                .animation(.playful, value: letter)
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
                            .font(.rounded(24, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.primary)
                    .disabled(isJoining)
                }
            }
            HStack(spacing: 8) {
                Button {
                    if !code.isEmpty { code.removeLast() }
                    errorText = nil
                } label: {
                    Label("Delete", systemImage: "delete.left.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .foregroundStyle(.primary)
            }
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
