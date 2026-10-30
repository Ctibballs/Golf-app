import SwiftUI
import GolfKit

/// Hole numbers in a row: tap one to start there. Holes in the round have a ring, and the
/// starting hole's marker slides across when you change it.
struct StartHolePicker: View {
    let holes: [Int]
    let playing: Set<Int>
    @Binding var selection: Int
    @Namespace private var marker

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(holes, id: \.self) { hole in
                        let selected = hole == selection
                        let inRound = playing.contains(hole)
                        Button {
                            withAnimation(.snappySpring) { selection = hole }
                        } label: {
                            Text("\(hole)")
                                .font(.figure(15, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Theme.onAccent : (inRound ? Color.primary : Color.secondary.opacity(0.6)))
                                .frame(width: 36, height: 36)
                                .background {
                                    if selected {
                                        Circle()
                                            .fill(Theme.fairway)
                                            .matchedGeometryEffect(id: "start", in: marker)
                                    } else if inRound {
                                        Circle().strokeBorder(Theme.outline, lineWidth: 1)
                                    }
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .id(hole)
                        .accessibilityLabel("Start on hole \(hole)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .sensoryFeedback(.selection, trigger: selection)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, hole in
                withAnimation(.snappySpring) { proxy.scrollTo(hole, anchor: .center) }
            }
        }
    }
}

/// A dot with a ring that ripples out every so often: "found from your location".
struct LocationPulse: View {
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Theme.fairway)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .stroke(Theme.fairway, lineWidth: 1)
                    .phaseAnimator([false, true]) { ring, expanded in
                        ring
                            .scaleEffect(expanded ? 2.8 : 1)
                            .opacity(expanded ? 0 : 0.8)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: 1.6) : .linear(duration: 0.01).delay(1.4)
                    }
            }
            .accessibilityHidden(true)
    }
}

/// "You're at …": the course your location puts you on, with a quick way to start.
struct CourseHereRow: View {
    let course: Course
    var actionTitle = "Tee off"
    let action: () -> Void
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    LocationPulse(size: 7)
                    Eyebrow("You're at", color: Theme.fairway)
                }
                Text(course.name).font(.headline).lineLimit(1)
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .buttonStyle(PrimaryButtonStyle(height: 38))
                .frame(width: 100)
        }
        .padding(.leading, 16)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.fairway).frame(width: 2)
        }
        .contextMenu {
            if let onDismiss {
                Button("Not here", systemImage: "location.slash", action: onDismiss)
            }
        }
    }

    private var detail: String {
        var parts = [course.gameType.displayName, "\(course.holeCount) holes", "Par \(course.par)"]
        if !course.locality.isEmpty { parts.append(course.locality) }
        return parts.joined(separator: " · ")
    }
}
