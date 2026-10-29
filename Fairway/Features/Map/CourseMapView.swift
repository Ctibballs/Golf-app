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
                VStack(spacing: 10) {
                    if let focus, let hole = layout.hole(focus) {
                        measureBar(hole)
                    }
                    holeCarousel(layout)
                }
                .padding(.bottom, 8)
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
        HStack(spacing: 14) {
            if let origin = measureOrigin(hole), let distances = hole.greenDistances(from: origin) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(origin == hole.teePoint ? "From the tee" : "From you").font(.caption2.weight(.bold)).opacity(0.8)
                    Text("\(app.units.distanceNumber(distances.front)) · \(app.units.distanceNumber(distances.center)) · \(app.units.distanceNumber(distances.back)) \(app.units.system.distanceUnit)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
            }
            Spacer()
            if let weather, let bearing = hole.bearing {
                WindBadge(speed: weather.current.windSpeed, fromDirection: weather.current.windDirection, units: app.units, holeBearing: bearing)
            } else if target == nil {
                Text("Tap the map to measure").font(.caption.weight(.semibold)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func holeCarousel(_ layout: CourseLayout) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(layout.holes) { hole in
                    let info = course.hole(hole.number)
                    Button {
                        withAnimation(.snappySpring) { focus = hole.number }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hole \(hole.number)").font(.headline)
                            HStack(spacing: 6) {
                                Text("Par \(info?.par ?? hole.par ?? 4)")
                                if let length = info?.length(for: course.defaultTee) ?? hole.length {
                                    Text("· \(app.units.distance(length))")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            if let si = info?.strokeIndex {
                                Text("Stroke index \(si)").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 130, alignment: .leading)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(focus == hole.number ? Theme.fairway : .clear, lineWidth: 2.5))
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.primary)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.92)
                            .opacity(phase.isIdentity ? 1 : 0.7)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
        }
        .scrollTargetBehavior(.viewAligned)
        .frame(height: 96)
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
