import SwiftUI
import MapKit
import GolfKit

/// A shot with its stroke number, for drawing.
struct NumberedShot: Identifiable {
    let number: Int
    let shot: Shot
    var id: UUID { shot.id }
}

/// Someone else's live position on the course.
struct PlayerPin: Identifiable {
    let id: UUID
    let name: String
    let avatar: Avatar
    let location: GeoPoint
}

/// One hole on the map, rotated so the green is at the top. Shows tracked shots, your
/// position, friends, and a tap-to-measure line (you → target → green).
struct HoleMapView: View {
    let course: Course
    let layout: CourseLayout
    let holeNumber: Int
    var shots: [Shot] = []
    var holeLocation: GeoPoint?
    var position: GeoPoint?
    var others: [PlayerPin] = []
    @Binding var target: GeoPoint?
    let units: UnitFormatter
    /// When set, taps place your ball instead of a measuring target (no-GPS mode).
    var onPlaceBall: ((GeoPoint) -> Void)?
    var interactive = true

    @State private var camera: MapCameraPosition = .automatic

    private var hole: HoleLayout? { layout.hole(holeNumber) }

    private var numberedShots: [NumberedShot] {
        ShotTracking.linked(shots, holeLocation: holeLocation).enumerated().map { NumberedShot(number: $0.offset + 1, shot: $0.element) }
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: interactive ? [.pan, .zoom, .rotate] : []) {
                CourseLayoutContent(layout: layout, focusHole: holeNumber, showsHoleNumbers: false)

                if let green = hole?.greenCenter {
                    Annotation("", coordinate: green.coordinate, anchor: .bottom) { PinMarker() }
                }

                ForEach(numberedShots) { item in
                    if let end = item.shot.end, let distance = item.shot.distance {
                        MapPolyline(coordinates: [item.shot.start.coordinate, end.coordinate])
                            .stroke(item.shot.isPutt ? Color.white.opacity(0.85) : MapPalette.shot, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        if distance > 8 {
                            Annotation("", coordinate: GeoMath.interpolate(item.shot.start, end, fraction: 0.5).coordinate) {
                                DistanceCallout(text: item.shot.isPutt ? units.shortDistance(distance) : units.distance(distance))
                            }
                        }
                    }
                    Annotation("", coordinate: item.shot.start.coordinate) {
                        BallMarker(label: "\(item.number)", color: .white, size: 18)
                    }
                }

                if let position, let target {
                    MapPolyline(coordinates: [position.coordinate, target.coordinate])
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    Annotation("", coordinate: GeoMath.interpolate(position, target, fraction: 0.5).coordinate) {
                        DistanceCallout(text: units.distance(GeoMath.distance(position, target)), tint: Theme.deepGreen)
                    }
                    if let green = hole?.greenCenter {
                        MapPolyline(coordinates: [target.coordinate, green.coordinate])
                            .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
                        Annotation("", coordinate: GeoMath.interpolate(target, green, fraction: 0.5).coordinate) {
                            DistanceCallout(text: units.distance(GeoMath.distance(target, green)))
                        }
                    }
                    Annotation("", coordinate: target.coordinate) {
                        Image(systemName: "scope")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }

                ForEach(others) { player in
                    Annotation(player.name, coordinate: player.location.coordinate) {
                        AvatarView(avatar: player.avatar, size: 26, showsRing: true)
                    }
                }

                if let position {
                    Annotation("", coordinate: position.coordinate) {
                        YouMarker()
                    }
                }
            }
            .mapStyle(course.preferredMapStyle)
            .mapControls { MapCompass() }
            .onTapGesture { screenPoint in
                guard interactive, let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                let point = GeoPoint(coordinate)
                if let onPlaceBall {
                    onPlaceBall(point)
                } else {
                    withAnimation(.snappySpring) { target = point }
                }
            }
        }
        .onAppear { camera = holeCamera }
        .onChange(of: holeNumber) {
            withAnimation(.easeInOut(duration: 0.9)) { camera = holeCamera }
        }
    }

    private var holeCamera: MapCameraPosition {
        if let camera = hole?.camera() { return .camera(camera) }
        if let bounds = layout.bounds { return .region(bounds.region()) }
        return .automatic
    }
}

/// Pulsing dot for your position.
struct YouMarker: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 34, height: 34)
                .scaleEffect(pulse ? 1.2 : 0.7)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(Color.blue)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(radius: 2)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Front / centre / back of the green, big and glanceable.
struct GreenDistancesView: View {
    let distances: GreenDistances
    let units: UnitFormatter
    var playsLike: Double?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                column("Front", distances.front, emphasized: false)
                column("Centre", distances.center, emphasized: true)
                column("Back", distances.back, emphasized: false)
            }
            if let playsLike, abs(playsLike - distances.center) >= 3 {
                Text("Plays like \(units.distance(playsLike))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                    .transition(.opacity)
            }
        }
    }

    private func column(_ title: String, _ metres: Double, emphasized: Bool) -> some View {
        VStack(spacing: 2) {
            Eyebrow(title)
            Text(units.distanceNumber(metres))
                .font(emphasized ? Font.display(46, weight: .regular) : Font.figure(22, weight: .regular))
                .foregroundStyle(emphasized ? .primary : .secondary)
                .contentTransition(.numericText(value: metres))
                .animation(.snappySpring, value: Int(metres))
        }
        .frame(maxWidth: .infinity)
    }
}
