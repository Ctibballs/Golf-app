import SwiftUI
import MapKit
import GolfKit

/// Explore every hole of a course: swipe through holes, tap to measure, see friends.
struct CourseMapView: View {
    @Environment(AppModel.self) private var app
    let course: Course
    var players: [Participant] = []

    @State private var layout: CourseLayout?
    @State private var isLoading = true
    @State private var focus: Int?
    @State private var camera: MapCameraPosition = .automatic
    @State private var target: GeoPoint?
    @State private var satellite = true
    @State private var weather: WeatherReport?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let layout {
                map(layout)
                    .ignoresSafeArea(edges: .bottom)
                VStack(spacing: 0) {
                    if let focus, let hole = layout.hole(focus) {
                        measureBar(hole)
                        Hairline()
                    }
                    holeStrip(layout)
                }
                .background(.regularMaterial)
                .overlay(alignment: .top) { Hairline() }
            } else if isLoading {
                ProgressView("Mapping the course…").controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    title: "No map yet",
                    message: "This course hasn't been mapped hole-by-hole on OpenStreetMap. Anyone can add it at openstreetmap.org, and it will appear here.",
                    systemImage: "map"
                )
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Satellite", isOn: $satellite)
                    Button("Whole course", systemImage: "map") { showOverview() }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }
            }
        }
        .task { await load() }
        .onChange(of: focus) { _, hole in
            target = nil
            guard let hole, let camera = layout?.hole(hole)?.camera() else { return }
            withAnimation(.easeInOut(duration: 1.0)) { self.camera = .camera(camera) }
        }
    }

    private func map(_ layout: CourseLayout) -> some View {
        MapReader { proxy in
            Map(position: $camera) {
                CourseLayoutContent(layout: layout, focusHole: focus)
                if let focus, let hole = layout.hole(focus) {
                    if let green = hole.greenCenter {
                        Annotation("", coordinate: green.coordinate, anchor: .bottom) { PinMarker() }
                    }
                    if let origin = measureOrigin(hole), let target {
                        MapPolyline(coordinates: [origin.coordinate, target.coordinate])
                            .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        Annotation("", coordinate: GeoMath.interpolate(origin, target, fraction: 0.5).coordinate) {
                            DistanceCallout(text: app.units.distance(GeoMath.distance(origin, target)), tint: Theme.deepGreen)
                        }
                        if let green = hole.greenCenter {
                            MapPolyline(coordinates: [target.coordinate, green.coordinate])
                                .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
                            Annotation("", coordinate: GeoMath.interpolate(target, green, fraction: 0.5).coordinate) {
                                DistanceCallout(text: app.units.distance(GeoMath.distance(target, green)))
                            }
                        }
                        Annotation("", coordinate: target.coordinate) {
                            Image(systemName: "scope").font(.title2.weight(.bold)).foregroundStyle(.white).shadow(radius: 2)
                        }
                    }
                }
                ForEach(players) { player in
                    if let location = player.lastLocation {
                        Annotation(player.name, coordinate: location.coordinate) {
                            AvatarView(avatar: player.avatar, size: 30, showsRing: true)
                        }
                    }
                }
                UserAnnotation()
            }
            .mapStyle(satellite ? course.preferredMapStyle : .standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .onTapGesture { screenPoint in
                guard focus != nil, let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                withAnimation(.snappySpring) { target = GeoPoint(coordinate) }
            }
        }
    }

    /// Measure from you if you're on the hole, otherwise from the tee.
    private func measureOrigin(_ hole: HoleLayout) -> GeoPoint? {
        if let me = app.location.point, let tee = hole.teePoint, GeoMath.distance(me, tee) < 700 { return me }
        return hole.teePoint
    }

    private func measureBar(_ hole: HoleLayout) -> some View {
        let info = course.hole(hole.number)
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Hole")
                Text("\(hole.number)")
                    .font(.display(36, weight: .regular))
                    .contentTransition(.numericText(value: Double(hole.number)))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(holeFacts(hole, info: info)).font(.subheadline.weight(.medium)).monospacedDigit()
                if let origin = measureOrigin(hole), let distances = hole.greenDistances(from: origin) {
                    Text("\(origin == hole.teePoint ? "From the tee" : "From you"): \(app.units.distanceNumber(distances.front)) · \(app.units.distanceNumber(distances.center)) · \(app.units.distanceNumber(distances.back)) \(app.units.system.distanceUnit)")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let weather, let bearing = hole.bearing {
                WindBadge(speed: weather.current.windSpeed, fromDirection: weather.current.windDirection, units: app.units, holeBearing: bearing)
            } else if target == nil {
                Text("Tap to measure").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
        .transition(.opacity)
    }

    private func holeFacts(_ hole: HoleLayout, info: HoleInfo?) -> String {
        var parts = ["Par \(info?.par ?? hole.par ?? 4)"]
        if let length = info?.length(for: course.defaultTee) ?? hole.length { parts.append(app.units.distance(length)) }
        if let si = info?.strokeIndex { parts.append("S.I. \(si)") }
        return parts.joined(separator: " · ")
    }

    private func holeStrip(_ layout: CourseLayout) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(layout.holes) { hole in
                        let selected = focus == hole.number
                        Button {
                            withAnimation(.snappySpring) { focus = hole.number }
                        } label: {
                            Text("\(hole.number)")
                                .font(.figure(15, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Theme.onAccent : .primary)
                                .frame(width: 36, height: 36)
                                .background(selected ? Theme.fairway : .clear, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle())
                        .id(hole.number)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 10)
            }
            .onChange(of: focus) { _, hole in
                guard let hole else { return }
                withAnimation(.snappySpring) { proxy.scrollTo(hole, anchor: .center) }
            }
        }
    }

    private func showOverview() {
        focus = nil
        target = nil
        if let bounds = layout?.bounds {
            withAnimation(.easeInOut(duration: 1.0)) { camera = .region(bounds.region()) }
        }
    }

    private func load() async {
        isLoading = true
        let loaded = await app.layout(for: course)
        layout = loaded
        isLoading = false
        if let bounds = loaded?.bounds {
            camera = .region(bounds.region())
        }
        if let point = course.location ?? loaded?.bounds?.center {
            weather = await app.weather(at: point)
        }
        // Fly to the first hole after the overview has had a moment on screen.
        try? await Task.sleep(for: .milliseconds(900))
        if focus == nil, let first = loaded?.holes.first?.number {
            withAnimation(.snappySpring) { focus = first }
        }
    }
}
