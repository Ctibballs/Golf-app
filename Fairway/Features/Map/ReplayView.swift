import SwiftUI
import MapKit
import GolfKit

/// Animated replay of a round on the map: the ball flies along each shot, hole by hole.
/// With several rounds (a match), everyone's shots play side by side in their own colour.
struct ReplayView: View {
    @Environment(AppModel.self) private var app
    let rounds: [Round]
    let course: Course

    @State private var layout: CourseLayout?
    @State private var replay: GroupReplay?
    @State private var time: TimeInterval = 0
    @State private var playing = false
    @State private var speed = 1.0
    @State private var lastTick: Date?
    @State private var camera: MapCameraPosition = .automatic
    @State private var shownHole: Int?

    private var playerRounds: [Round] {
        rounds.filter { $0.hasShotData }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let layout, let replay, !replay.isEmpty {
                mapView(layout: layout, replay: replay)
                    .ignoresSafeArea(edges: .bottom)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
                    Color.clear
                        .onChange(of: context.date) { _, date in tick(date, replay: replay) }
                }
                .allowsHitTesting(false)
                controls(replay)
            } else if layout == nil && replay == nil {
                ProgressView("Preparing replay…").controlSize(.large).frame(maxHeight: .infinity)
            } else {
                EmptyStateView(title: "Nothing to replay", message: "Replays need shots marked with GPS (or tapped on the map) during the round.", systemImage: "play.slash")
                    .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("Replay")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .onChange(of: replay?.frames(at: time).hole) { _, hole in
            guard let hole, hole != shownHole else { return }
            shownHole = hole
            if let holeCamera = layout?.hole(hole)?.camera() {
                withAnimation(.easeInOut(duration: 0.9)) { camera = .camera(holeCamera) }
            }
        }
    }

    // MARK: - Map

    private func mapView(layout: CourseLayout, replay: GroupReplay) -> some View {
        let state = replay.frames(at: time)
        let entries: [ReplayEntry] = playerRounds.enumerated().compactMap { index, round in
            state.frames[round.playerID].map { ReplayEntry(index: index, round: round, frame: $0) }
        }
        let currentHole = state.hole.flatMap { layout.hole($0) }
        return Map(position: $camera) {
            // Only the hole being replayed: this map redraws every animation frame.
            if let currentHole {
                HoleLayoutContent(hole: currentHole)
                if let green = currentHole.greenCenter {
                    Annotation("", coordinate: green.coordinate, anchor: .bottom) { PinMarker() }
                }
            }
            ForEach(entries) { entry in
                ForEach(entry.frame.completed) { shot in
                    MapPolyline(coordinates: [shot.start.coordinate, shot.end.coordinate])
                        .stroke(entry.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    if !shot.isPutt && shot.distance > 30 {
                        Annotation("", coordinate: GeoMath.interpolate(shot.start, shot.end, fraction: 0.5).coordinate) {
                            DistanceCallout(text: app.units.distance(shot.distance), tint: entry.color.opacity(0.9))
                        }
                    }
                }
                if let active = entry.frame.active, let ball = entry.frame.ball {
                    MapPolyline(coordinates: [active.start.coordinate, ball.coordinate])
                        .stroke(entry.color.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6]))
                }
                if let ball = entry.frame.ball {
                    Annotation("", coordinate: ball.coordinate) {
                        FlyingBall(height: entry.frame.height, color: entry.color, label: playerRounds.count > 1 ? String(entry.round.playerName.prefix(1)) : nil)
                    }
                }
            }
        }
        .mapStyle(course.preferredMapStyle)
        .onAppear {
            if let first = replay.holes.first?.hole, let c = layout.hole(first)?.camera() {
                camera = .camera(c)
                shownHole = first
            }
        }
    }

    // MARK: - Controls

    private func controls(_ replay: GroupReplay) -> some View {
        let state = replay.frames(at: time)
        return VStack(spacing: 12) {
            if let hole = state.hole {
                HStack {
                    Text("Hole \(hole)").font(.headline)
                    Spacer()
                    ForEach(Array(playerRounds.enumerated()), id: \.element.id) { index, round in
                        if let frame = state.frames[round.playerID] {
                            HStack(spacing: 4) {
                                Circle().fill(MapPalette.player(index)).frame(width: 8, height: 8)
                                Text(shotLabel(frame, name: playerRounds.count > 1 ? round.playerName : nil))
                                    .font(.caption.weight(.semibold))
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(replay.holes, id: \.hole) { segment in
                        Button {
                            time = segment.start
                            lastTick = nil
                        } label: {
                            Text("\(segment.hole)")
                                .font(.caption.weight(.bold))
                                .frame(width: 30, height: 30)
                                .background(segment.hole == state.hole ? Theme.fairway : Color(uiColor: .tertiarySystemFill), in: Circle())
                                .foregroundStyle(segment.hole == state.hole ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 14) {
                Button {
                    if time >= replay.totalDuration { time = 0 }
                    lastTick = nil
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 52, height: 52)
                        .foregroundStyle(.white)
                        .background(Theme.heroGradient, in: Circle())
                }
                .buttonStyle(PressableStyle())

                Slider(value: Binding(get: { time }, set: { time = $0; lastTick = nil }), in: 0...max(0.1, replay.totalDuration))
                    .tint(Theme.fairway)

                Menu {
                    ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { value in
                        Button("\(value, specifier: "%g")×") { speed = value }
                    }
                } label: {
                    Text("\(speed, specifier: "%g")×")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 44, height: 36)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func shotLabel(_ frame: ReplayFrame, name: String?) -> String {
        let stroke = (frame.active?.strokeNumber ?? frame.completed.count)
        let prefix = name.map { "\($0) " } ?? ""
        if let active = frame.active {
            return "\(prefix)Shot \(stroke) · \(active.club?.shortName ?? active.lie.displayName)"
        }
        return "\(prefix)\(stroke) shot\(stroke == 1 ? "" : "s")"
    }

    // MARK: - Timing

    private func tick(_ date: Date, replay: GroupReplay) {
        guard playing else { return }
        defer { lastTick = date }
        guard let lastTick else { return }
        time = min(replay.totalDuration, time + date.timeIntervalSince(lastTick) * speed)
        if time >= replay.totalDuration { playing = false }
    }

    private func prepare() async {
        let loaded = await app.layout(for: course)
        let players = playerRounds.map { round in
            (id: round.playerID, shots: ReplayShot.from(scores: round.scores, playerID: round.playerID))
        }
        let order = rounds.first?.holeNumbers ?? course.holes.map(\.number)
        layout = loaded ?? CourseLayout(holes: [])
        replay = GroupReplay(players: players, holeOrder: order)
        try? await Task.sleep(for: .milliseconds(700))
        playing = true
    }
}

struct ReplayEntry: Identifiable {
    let index: Int
    let round: Round
    let frame: ReplayFrame
    var id: UUID { round.id }
    var color: Color { MapPalette.player(index) }
}

/// The ball in flight: lifted by its height with a shadow left on the ground.
struct FlyingBall: View {
    let height: Double
    let color: Color
    var label: String?

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: 12, height: 5)
                .offset(y: 4)
                .opacity(height > 0.05 ? 1 : 0)
            BallMarker(label: label, color: .white, size: 14 + CGFloat(height) * 8)
                .overlay(Circle().strokeBorder(color, lineWidth: 2.5))
                .offset(y: -CGFloat(height) * 46)
        }
    }
}
