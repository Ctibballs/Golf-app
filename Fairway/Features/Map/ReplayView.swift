import SwiftUI
import MapKit
import Observation
import GolfKit

/// Playback state for a replay. Only the views that draw the animation read `time`, so the
/// map itself redraws only when the hole changes.
@Observable
@MainActor
final class ReplayClock {
    var time: TimeInterval = 0
    var playing = false
    var speed = 1.0
    /// Bumped when the map camera moves, so the overlay re-projects while paused.
    var cameraRevision = 0
    @ObservationIgnored var lastTick: Date?

    func tick(_ date: Date, total: TimeInterval) {
        guard playing else {
            lastTick = nil
            return
        }
        defer { lastTick = date }
        guard let lastTick else { return }
        time = min(total, time + date.timeIntervalSince(lastTick) * speed)
        if time >= total { playing = false }
    }

    func seek(to value: TimeInterval) {
        time = value
        lastTick = nil
    }
}

/// Animated replay of a round on the map: the ball flies along each shot, hole by hole.
/// With several rounds (a match), everyone's shots play side by side in their own colour.
struct ReplayView: View {
    @Environment(AppModel.self) private var app
    let rounds: [Round]
    let course: Course

    @State private var layout: CourseLayout?
    @State private var replay: GroupReplay?
    @State private var clock = ReplayClock()
    @State private var camera: MapCameraPosition = .automatic
    @State private var shownHole: Int?

    private var playerRounds: [Round] {
        rounds.filter { $0.hasShotData }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let layout, let replay, !replay.isEmpty {
                map(layout: layout, replay: replay)
                    .ignoresSafeArea(edges: .bottom)
                ReplayTicker(clock: clock, total: replay.totalDuration)
                ReplayHoleWatcher(clock: clock, replay: replay) { hole in show(hole: hole, in: layout) }
                ReplayControls(clock: clock, replay: replay, rounds: playerRounds)
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
        .onDisappear { clock.playing = false }
    }

    private func map(layout: CourseLayout, replay: GroupReplay) -> some View {
        let hole = shownHole.flatMap { layout.hole($0) }
        return MapReader { proxy in
            Map(position: $camera) {
                if let hole {
                    HoleLayoutContent(hole: hole)
                    if let green = hole.greenCenter {
                        Annotation("", coordinate: green.coordinate, anchor: .bottom) { PinMarker() }
                    }
                }
            }
            .mapStyle(course.preferredMapStyle)
            .onMapCameraChange(frequency: .continuous) { clock.cameraRevision += 1 }
            .overlay {
                ReplayOverlay(clock: clock, replay: replay, rounds: playerRounds, proxy: proxy, units: app.units)
                    .allowsHitTesting(false)
            }
        }
    }

    private func show(hole: Int, in layout: CourseLayout) {
        guard hole != shownHole else { return }
        shownHole = hole
        if let holeCamera = layout.hole(hole)?.camera() {
            withAnimation(.easeInOut(duration: 0.9)) { camera = .camera(holeCamera) }
        }
    }

    private func prepare() async {
        guard replay == nil else { return }
        let loaded = await app.layout(for: course)
        let players = playerRounds.map { round in
            (id: round.playerID, shots: ReplayShot.from(scores: round.scores, playerID: round.playerID))
        }
        let order = rounds.first?.holeNumbers ?? course.holes.map(\.number)
        layout = loaded ?? CourseLayout(holes: [])
        replay = GroupReplay(players: players, holeOrder: order)
        try? await Task.sleep(for: .milliseconds(700))
        clock.playing = true
    }
}

/// Advances the clock every display frame while playing.
private struct ReplayTicker: View {
    let clock: ReplayClock
    let total: TimeInterval

    var body: some View {
        TimelineView(.animation(paused: !clock.playing)) { context in
            Color.clear
                .onChange(of: context.date) { _, date in clock.tick(date, total: total) }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}

/// Reports when playback moves to a new hole so the camera can follow.
private struct ReplayHoleWatcher: View {
    let clock: ReplayClock
    let replay: GroupReplay
    let onHole: (Int) -> Void

    var body: some View {
        let hole = replay.segment(at: clock.time)?.hole
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: hole, initial: true) { _, newHole in
                if let newHole { onHole(newHole) }
            }
    }
}

/// Shots and the flying ball, drawn in a Canvas over the map using the map's projection.
private struct ReplayOverlay: View {
    let clock: ReplayClock
    let replay: GroupReplay
    let rounds: [Round]
    let proxy: MapProxy
    let units: UnitFormatter

    struct Line {
        let from: CGPoint
        let to: CGPoint
        let color: Color
        let dashed: Bool
    }

    struct DistanceLabel {
        let text: String
        let at: CGPoint
        let color: Color
    }

    struct Ball {
        let ground: CGPoint
        let height: Double
        let color: Color
        let initial: String?
    }

    var body: some View {
        let scene = makeScene()
        Canvas { context, _ in
            for line in scene.lines {
                var path = Path()
                path.move(to: line.from)
                path.addLine(to: line.to)
                let dash: [CGFloat] = line.dashed ? [2, 6] : []
                context.stroke(path, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: dash))
                context.stroke(path, with: .color(line.color), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dash))
            }
            for label in scene.labels {
                let text = context.resolve(Text(label.text).font(.caption2.weight(.heavy)).foregroundColor(.white))
                let size = text.measure(in: CGSize(width: 200, height: 40))
                let rect = CGRect(x: label.at.x - size.width / 2 - 6, y: label.at.y - size.height / 2 - 3, width: size.width + 12, height: size.height + 6)
                context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(label.color.opacity(0.9)))
                context.draw(text, at: label.at)
            }
            for ball in scene.balls {
                let lift = CGFloat(ball.height) * 46
                let radius = 7 + CGFloat(ball.height) * 4
                if ball.height > 0.05 {
                    let shadow = CGRect(x: ball.ground.x - 6, y: ball.ground.y - 2.5, width: 12, height: 5)
                    context.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.35)))
                }
                let center = CGPoint(x: ball.ground.x, y: ball.ground.y - lift)
                let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: disc), with: .color(.white))
                context.stroke(Path(ellipseIn: disc), with: .color(ball.color), lineWidth: 2.5)
                if let initial = ball.initial {
                    context.draw(Text(initial).font(.system(size: radius, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.75)), at: center)
                }
            }
        }
    }

    /// Projects the current frame into screen points. Reading the clock here is what makes
    /// only this overlay redraw on every tick.
    private func makeScene() -> (lines: [Line], labels: [DistanceLabel], balls: [Ball]) {
        _ = clock.cameraRevision
        let state = replay.frames(at: clock.time)
        var lines: [Line] = []
        var labels: [DistanceLabel] = []
        var balls: [Ball] = []

        for (index, round) in rounds.enumerated() {
            guard let frame = state.frames[round.playerID] else { continue }
            let color = MapPalette.player(index)
            for shot in frame.completed {
                guard let a = point(shot.start), let b = point(shot.end) else { continue }
                lines.append(Line(from: a, to: b, color: color, dashed: false))
                if !shot.isPutt && shot.distance > 30 {
                    let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    labels.append(DistanceLabel(text: units.distance(shot.distance), at: middle, color: color))
                }
            }
            if let active = frame.active, let ball = frame.ball, let a = point(active.start), let b = point(ball) {
                lines.append(Line(from: a, to: b, color: color.opacity(0.85), dashed: true))
            }
            if let ball = frame.ball, let ground = point(ball) {
                let initial = rounds.count > 1 ? String(round.playerName.prefix(1)) : nil
                balls.append(Ball(ground: ground, height: frame.height, color: color, initial: initial))
            }
        }
        return (lines, labels, balls)
    }

    private func point(_ geo: GeoPoint) -> CGPoint? {
        proxy.convert(geo.coordinate, to: .local)
    }
}

private struct ReplayControls: View {
    let clock: ReplayClock
    let replay: GroupReplay
    let rounds: [Round]

    var body: some View {
        let state = replay.frames(at: clock.time)
        VStack(spacing: 12) {
            if let hole = state.hole {
                HStack {
                    Text("Hole \(hole)").font(.headline)
                    Spacer()
                    ForEach(Array(rounds.enumerated()), id: \.element.id) { index, round in
                        if let frame = state.frames[round.playerID] {
                            HStack(spacing: 4) {
                                Circle().fill(MapPalette.player(index)).frame(width: 8, height: 8)
                                Text(shotLabel(frame, name: rounds.count > 1 ? round.playerName : nil))
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(replay.holes, id: \.hole) { segment in
                        Button {
                            clock.seek(to: segment.start)
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
                    if clock.time >= replay.totalDuration { clock.seek(to: 0) }
                    clock.lastTick = nil
                    clock.playing.toggle()
                } label: {
                    Image(systemName: clock.playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 52, height: 52)
                        .foregroundStyle(.white)
                        .background(Theme.heroGradient, in: Circle())
                }
                .buttonStyle(PressableStyle())

                Slider(value: Binding(get: { clock.time }, set: { clock.seek(to: $0) }), in: 0...max(0.1, replay.totalDuration))
                    .tint(Theme.fairway)

                Menu {
                    ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { value in
                        Button("\(value, specifier: "%g")×") { clock.speed = value }
                    }
                } label: {
                    Text("\(clock.speed, specifier: "%g")×")
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
        let stroke = frame.active?.strokeNumber ?? frame.completed.count
        let prefix = name.map { "\($0) " } ?? ""
        if let active = frame.active {
            return "\(prefix)Shot \(stroke) · \(active.club?.shortName ?? active.lie.displayName)"
        }
        return "\(prefix)\(stroke) shot\(stroke == 1 ? "" : "s")"
    }
}
