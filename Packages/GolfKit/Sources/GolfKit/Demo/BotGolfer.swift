import Foundation

/// Generates believable, deterministic scores and GPS shots for simulated players.
/// Used by the offline demo (friends who "join" your lobby) and sample history.
public enum BotGolfer {
    public static func holeScore(
        playerID: UUID,
        handicap: Double?,
        hole: HoleInfo,
        gameType: GameType,
        layout: HoleLayout?,
        salt: Int = 0,
        startTime: Date = Date()
    ) -> HoleScore {
        var rng = SplitMix64(playerID, salt: hole.number * 7919 + salt)
        let h = handicap ?? 18

        let expectedOver: Double
        switch gameType {
        case .golf: expectedOver = h / 18 * 1.05 + 0.08
        case .pitchAndPutt: expectedOver = h / 18 * 0.7 + 0.05
        case .miniGolf: expectedOver = 0.35 + h / 40
        }
        var strokes = hole.par + Int(rng.gaussian(mean: expectedOver, deviation: 0.8).rounded())
        strokes = max(max(1, hole.par - 2), min(hole.par + 4, strokes))
        if let cap = gameType.maxStrokesPerHole { strokes = min(cap, strokes) }

        guard gameType.tracksGreens else {
            return HoleScore(holeNumber: hole.number, strokes: strokes)
        }

        // Putts: mostly two, sometimes one or three; leave at least one shot to reach the green.
        let roll = Double.random(in: 0...1, using: &rng)
        var putts = roll < 0.24 ? 1 : (roll < 0.86 ? 2 : 3)
        putts = strokes == 1 ? 0 : min(putts, strokes - 1)
        let toGreen = strokes - putts

        var fairway: FairwayResult?
        if gameType.tracksFairways && hole.par >= 4 {
            let f = Double.random(in: 0...1, using: &rng)
            fairway = f < 0.52 - h / 100 ? .hit : (f < 0.76 ? .left : .right)
        }

        var shots: [Shot] = []
        var holeLocation: GeoPoint?
        if let layout, let tee = layout.teePoint, let green = layout.greenCenter, gameType.supportsShotTracking {
            let pathLength = layout.length ?? GeoMath.distance(tee, green)
            let path = layout.path.count >= 2 ? layout.path : [tee, green]
            holeLocation = GeoMath.destination(from: green, bearing: Double.random(in: 0..<360, using: &rng), distance: Double.random(in: 0...5, using: &rng))

            var positions: [GeoPoint] = [tee]
            for k in 1..<max(1, toGreen) {
                // Approach positions spread along the hole with lateral scatter.
                let fraction = Double(k) / Double(toGreen) * Double.random(in: 0.92...1.04, using: &rng)
                let along = GeoMath.point(along: path, distance: pathLength * min(0.95, fraction)) ?? green
                let lateral = rng.gaussian(mean: 0, deviation: 9 + h / 2)
                let bearing = (layout.bearing ?? 0) + (lateral >= 0 ? 90 : -90)
                positions.append(GeoMath.destination(from: along, bearing: bearing, distance: abs(lateral)))
            }
            if putts > 0 {
                // First putt starts somewhere on the green; later putts creep closer.
                let firstPutt = GeoMath.destination(from: green, bearing: Double.random(in: 0..<360, using: &rng), distance: Double.random(in: 3...12, using: &rng))
                positions.append(firstPutt)
                for p in 1..<putts {
                    let remaining = Double(putts - p) / Double(putts)
                    positions.append(GeoMath.interpolate(holeLocation!, firstPutt, fraction: remaining * 0.25))
                }
            }

            var time = startTime
            for (index, start) in positions.enumerated() {
                let isPutt = index >= toGreen
                let lie: Lie = index == 0 ? .tee : (isPutt ? .green : layout.lie(at: start))
                let end = index + 1 < positions.count ? positions[index + 1] : holeLocation!
                let club: Club = isPutt ? .putter : (index == 0 && hole.par >= 4 ? .driver : Club.suggested(for: GeoMath.distance(start, end)))
                shots.append(Shot(start: start, end: end, club: club, lie: lie, timestamp: time))
                time = time.addingTimeInterval(isPutt ? 40 : 110)
            }
        }

        return HoleScore(
            holeNumber: hole.number,
            strokes: strokes,
            putts: putts,
            fairway: fairway,
            sandShots: shots.contains { $0.lie == .sand } ? 1 : 0,
            shots: shots,
            holeLocation: holeLocation
        )
    }
}
