import SwiftUI
import MapKit
import GolfKit

/// Colours for drawing a course on the map.
enum MapPalette {
    static let fairway = Color(hex: 0x58D27D)
    static let green = Color(hex: 0x86F5A4)
    static let tee = Color(hex: 0xB4F0C4)
    static let sand = Color(hex: 0xF1DDA8)
    static let water = Color(hex: 0x3D9BFF)
    static let path = Color.white
    static let shot = Color(hex: 0xFFD45E)

    /// One colour per player in multi-player replays.
    static let players: [Color] = [Color(hex: 0xFFD45E), Color(hex: 0xFF5A4E), Color(hex: 0x4FA3FF), Color(hex: 0xC56CF0), Color(hex: 0x14B8A6), Color(hex: 0xFF8A3D)]

    static func player(_ index: Int) -> Color { players[index % players.count] }
}

/// Fairways, greens, tees, bunkers and water for a whole course. The focused hole is
/// drawn brighter than the rest.
struct CourseLayoutContent: MapContent {
    let layout: CourseLayout
    var focusHole: Int?
    var showsHoleNumbers = true
    var showsCentreLines = true

    var body: some MapContent {
        ForEach(Array(layout.water.enumerated()), id: \.offset) { _, polygon in
            MapPolygon(coordinates: polygon.coordinates)
                .foregroundStyle(MapPalette.water.opacity(0.55))
        }
        ForEach(layout.holes) { hole in
            HoleLayoutContent(hole: hole, emphasis: emphasis(for: hole.number), showsCentreLine: showsCentreLines && (focusHole == nil || focusHole == hole.number))
        }
        ForEach(Array(layout.bunkers.enumerated()), id: \.offset) { _, polygon in
            MapPolygon(coordinates: polygon.coordinates)
                .foregroundStyle(MapPalette.sand.opacity(0.85))
        }
        if showsHoleNumbers {
            ForEach(layout.holes) { hole in
                if let tee = hole.teePoint {
                    Annotation("", coordinate: tee.coordinate, anchor: .center) {
                        HoleNumberBadge(number: hole.number, isFocused: hole.number == focusHole)
                    }
                }
            }
        }
    }

    private func emphasis(for number: Int) -> Double {
        guard let focusHole else { return 1 }
        return number == focusHole ? 1 : 0.45
    }
}

struct HoleLayoutContent: MapContent {
    let hole: HoleLayout
    var emphasis: Double = 1
    var showsCentreLine = true

    var body: some MapContent {
        ForEach(Array(hole.fairways.enumerated()), id: \.offset) { _, polygon in
            MapPolygon(coordinates: polygon.coordinates)
                .foregroundStyle(MapPalette.fairway.opacity(0.55 * emphasis))
        }
        ForEach(Array(hole.tees.enumerated()), id: \.offset) { _, polygon in
            MapPolygon(coordinates: polygon.coordinates)
                .foregroundStyle(MapPalette.tee.opacity(0.75 * emphasis))
        }
        ForEach(Array(hole.greens.enumerated()), id: \.offset) { _, polygon in
            MapPolygon(coordinates: polygon.coordinates)
                .foregroundStyle(MapPalette.green.opacity(0.8 * emphasis))
                .stroke(.white.opacity(0.9 * emphasis), lineWidth: 1.5)
        }
        ForEach(Array(hole.bunkers.enumerated()), id: \.offset) { _, polygon in
            MapPolygon(coordinates: polygon.coordinates)
                .foregroundStyle(MapPalette.sand.opacity(0.9 * emphasis))
        }
        ForEach(Array(hole.water.enumerated()), id: \.offset) { _, polygon in
            MapPolygon(coordinates: polygon.coordinates)
                .foregroundStyle(MapPalette.water.opacity(0.5 * emphasis))
        }
        if showsCentreLine && hole.path.count >= 2 {
            MapPolyline(coordinates: hole.path.coordinates)
                .stroke(MapPalette.path.opacity(0.7 * emphasis), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 6]))
        }
    }
}

struct HoleNumberBadge: View {
    let number: Int
    var isFocused = false

    var body: some View {
        Text("\(number)")
            .font(.system(size: isFocused ? 13 : 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(isFocused ? Color.black : .white)
            .frame(width: isFocused ? 26 : 18, height: isFocused ? 26 : 18)
            .background(isFocused ? Color.white : Color.black.opacity(0.55), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            .animation(.snappySpring, value: isFocused)
    }
}

/// The pin on the green.
struct PinMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "flag.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.flag)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            Circle().fill(.black.opacity(0.6)).frame(width: 6, height: 3)
        }
    }
}

/// A ball marker with a number, for shots.
struct BallMarker: View {
    var label: String?
    var color: Color = .white
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1)
            if let label {
                Text(label)
                    .font(.system(size: size * 0.52, weight: .bold).monospacedDigit())
                    .foregroundStyle(.black.opacity(0.75))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

/// Distance callout drawn mid-way along a shot or measuring line.
struct DistanceCallout: View {
    let text: String
    var tint: Color = .black

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// A static overview of the whole course, for headers.
struct CourseOverviewMap: View {
    let course: Course
    let layout: CourseLayout

    var body: some View {
        Map(initialPosition: initialPosition, interactionModes: []) {
            CourseLayoutContent(layout: layout, showsHoleNumbers: true, showsCentreLines: false)
        }
        .mapStyle(course.source == .demo ? .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false) : .imagery(elevation: .flat))
        .allowsHitTesting(false)
    }

    private var initialPosition: MapCameraPosition {
        if let bounds = layout.bounds { return .region(bounds.region(padding: 1.15)) }
        if let location = course.location {
            return .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
        }
        return .automatic
    }
}

extension Course {
    /// Satellite imagery for real courses; a clean drawn map for the demo courses (whose
    /// fairways are synthetic and wouldn't match the imagery underneath).
    var preferredMapStyle: MapStyle {
        source == .demo
            ? .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
            : .imagery(elevation: .realistic)
    }
}
