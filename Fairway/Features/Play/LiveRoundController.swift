import SwiftUI
import UIKit
import Observation
import GolfKit

/// Drives a round in progress: the current hole, scores for everyone this device keeps,
/// GPS shot tracking, and syncing to a match when there is one.
@Observable
@MainActor
final class LiveRoundController {
    let roundID: UUID
    let session: MatchSession?
    private(set) var currentHole: Int
    private(set) var direction: Edge = .trailing
    private(set) var layout: CourseLayout?
    private(set) var weather: WeatherReport?
    var selectedClub: Club?
    var selectedLie: Lie?
    /// Ball position placed by tapping the map (no GPS, or practising at home).
    var manualBall: GeoPoint?
    var placeBallMode = false
    var measureTarget: GeoPoint?
    private(set) var celebrationTrigger = 0
    private(set) var celebrationText: String?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var lastSharedLocation: (point: GeoPoint, time: Date)?
    @ObservationIgnored private var cachedClubAverages: [Club: Double]?

    /// Your average distance per club, from past GPS rounds (computed once per round).
    private var clubAverages: [Club: Double] {
        if let cachedClubAverages { return cachedClubAverages }
        let averages = Dictionary(uniqueKeysWithValues: StatsEngine.clubDistances(in: app.library.rounds).map { ($0.club, $0.average) })
        cachedClubAverages = averages
        return averages
    }

    init(app: AppModel, roundID: UUID, session: MatchSession?) {
        self.app = app
        self.roundID = roundID
        self.session = session
        let round = app.round(roundID)
        self.currentHole = round?.nextHoleToPlay ?? round?.holeNumbers.first ?? 1
    }

    // MARK: - Round data

    var round: Round? { app.round(roundID) }
    var course: Course { round?.course ?? session?.match.course ?? DemoData.golfCourse }
    var holeNumbers: [Int] { round?.holeNumbers ?? session?.match.holeNumbers ?? [] }
    var hole: HoleInfo? { course.hole(currentHole) }
    var par: Int { hole?.par ?? course.gameType.defaultPar }
    var holeLayout: HoleLayout? { layout?.hole(currentHole) }
    var myID: UUID { app.profile.id }
    var units: UnitFormatter { app.units }
    var tracksShots: Bool { course.gameType.supportsShotTracking }

    var holeIndex: Int { holeNumbers.firstIndex(of: currentHole) ?? 0 }
    var isFirstHole: Bool { holeIndex == 0 }
    var isLastHole: Bool { holeIndex == holeNumbers.count - 1 }
    var allHolesScored: Bool { holeNumbers.allSatisfy { score(for: myID, hole: $0) != nil } }

    /// Everyone scored on this device: you first, then guests in a match.
    var players: [Participant] {
        if let session, !session.scoredHere.isEmpty { return session.scoredHere }
        var me = app.meAsParticipant(for: course.gameType)
        me.scores = round?.scores ?? []
        return [me]
    }

    func score(for playerID: UUID, hole: Int) -> HoleScore? {
        if playerID == myID { return round?.score(for: hole) }
        return session?.snapshot.participant(playerID)?.score(for: hole)
    }

    /// Strokes received on the current hole, for showing handicap dots.
    func strokesReceived(_ player: Participant) -> Int {
        guard let session, session.match.useHandicaps else { return 0 }
        return PlayingHandicap.strokeAllocation(for: player, in: session.match)[currentHole] ?? 0
    }

    // MARK: - Location

    /// Your position: the tapped ball in place-ball mode, otherwise GPS.
    var position: GeoPoint? {
        if placeBallMode { return manualBall }
        return app.location.point ?? manualBall
    }

    var greenDistances: GreenDistances? {
        guard let position, let holeLayout else { return nil }
        let distances = holeLayout.greenDistances(from: position)
        // Hide silly numbers when you're nowhere near this hole.
        guard let d = distances, d.center < 800 else { return nil }
        return d
    }

    var playsLike: Double? {
        guard let distances = greenDistances, let weather, let bearing = holeLayout?.bearing else { return nil }
        let effect = WindEffect(windSpeed: weather.current.windSpeed, windFromDirection: weather.current.windDirection, shotBearing: bearing)
        return effect.playsLike(distance: distances.center)
    }

    /// Distance from where you last hit to where you're standing: "that drive went 231 m".
    var liveShotDistance: Double? {
        guard let last = shots.last, let position else { return nil }
        let d = GeoMath.distance(last.start, position)
        return d > 3 ? d : nil
    }

    var shots: [Shot] { score(for: myID, hole: currentHole)?.shots ?? [] }

    var suggestedClub: Club? {
        guard tracksShots, let distances = greenDistances else {
            return shots.isEmpty && par >= 4 ? .driver : nil
        }
        if shots.isEmpty && par >= 4 && distances.center > 230 { return .driver }
        if let position, let holeLayout, holeLayout.lie(at: position) == .green { return .putter }
        return Club.suggested(for: playsLike ?? distances.center, averages: clubAverages)
    }

    // MARK: - Lifecycle

    func load() async {
        // Start GPS first so a fix is arriving while the map and weather load.
        if tracksShots { app.location.start() }
        if app.library.settings.keepScreenAwake { UIApplication.shared.isIdleTimerDisabled = true }
        session?.startPolling()
        syncCurrentHole()

        layout = await app.layout(for: course)
        if tracksShots && app.location.isDenied {
            // No GPS: mark shots by tapping the map, starting from the tee.
            placeBallMode = true
            manualBall = holeLayout?.teePoint
        }
        if let location = course.location ?? layout?.bounds?.center {
            weather = await app.weather(at: location)
        }
    }

    func unload() {
        app.location.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Called as GPS updates arrive; shares your position with the group now and then.
    func locationDidChange() {
        guard let session, app.library.settings.online.shareLiveLocation, let point = app.location.point else { return }
        if let last = lastSharedLocation, Date().timeIntervalSince(last.time) < 20, GeoMath.distance(last.point, point) < 25 {
            return
        }
        lastSharedLocation = (point, Date())
        session.setCurrentHole(currentHole, location: point, for: myID)
    }

    // MARK: - Navigation

    func go(to hole: Int) {
        guard hole != currentHole, holeNumbers.contains(hole) else { return }
        direction = (holeNumbers.firstIndex(of: hole) ?? 0) > holeIndex ? .trailing : .leading
        withAnimation(.snappySpring) {
            currentHole = hole
            measureTarget = nil
            selectedClub = nil
            selectedLie = nil
            manualBall = holeLayout?.teePoint.flatMap { placeBallMode ? $0 : nil }
        }
        syncCurrentHole()
    }

    func next() {
        guard !isLastHole else { return }
        go(to: holeNumbers[holeIndex + 1])
    }

    func previous() {
        guard !isFirstHole else { return }
        go(to: holeNumbers[holeIndex - 1])
    }

    private func syncCurrentHole() {
        guard let session else { return }
        let share = app.library.settings.online.shareLiveLocation
        for player in session.scoredHere {
            session.setCurrentHole(currentHole, location: player.id == myID && share ? app.location.point : nil, for: player.id)
        }
    }

    // MARK: - Scoring

    func setScore(_ score: HoleScore, for playerID: UUID) {
        let previous = self.score(for: playerID, hole: score.holeNumber)
        if playerID == myID, var round {
            round.setScore(score)
            app.saveRound(round)
        }
        session?.setScore(score, for: playerID)
        if playerID == myID { celebrateIfNeeded(old: previous, new: score) }
    }

    func adjustStrokes(_ delta: Int, for playerID: UUID) {
        var score = self.score(for: playerID, hole: currentHole) ?? HoleScore(holeNumber: currentHole, strokes: par - delta)
        var strokes = max(1, score.strokes + delta)
        if let cap = course.gameType.maxStrokesPerHole { strokes = min(cap, strokes) }
        score.strokes = strokes
        if let putts = score.putts, putts >= strokes { score.putts = max(0, strokes - 1) }
        setScore(score, for: playerID)
    }

    func adjustPutts(_ delta: Int, for playerID: UUID) {
        var score = self.score(for: playerID, hole: currentHole) ?? HoleScore(holeNumber: currentHole, strokes: par)
        let putts = max(0, min(score.strokes, (score.putts ?? (delta > 0 ? 1 : 2)) + delta))
        score.putts = putts
        setScore(score, for: playerID)
    }

    func setFairway(_ result: FairwayResult, for playerID: UUID) {
        var score = self.score(for: playerID, hole: currentHole) ?? HoleScore(holeNumber: currentHole, strokes: par)
        score.fairway = score.fairway == result ? nil : result
        setScore(score, for: playerID)
    }

    func adjustPenalties(_ delta: Int, for playerID: UUID) {
        var score = self.score(for: playerID, hole: currentHole) ?? HoleScore(holeNumber: currentHole, strokes: par)
        let penalties = max(0, score.penalties + delta)
        score.strokes = max(1, score.strokes + (penalties - score.penalties))
        score.penalties = penalties
        setScore(score, for: playerID)
    }

    // MARK: - GPS shots

    func markShot() {
        guard let point = position else { return }
        var score = self.score(for: myID, hole: currentHole) ?? HoleScore(holeNumber: currentHole, strokes: 0)
        let lie: Lie
        if let selectedLie {
            lie = selectedLie
        } else if score.shots.isEmpty {
            lie = .tee
        } else if app.library.settings.autoDetectLie, let holeLayout {
            lie = holeLayout.lie(at: point)
        } else {
            lie = .fairway
        }
        let club = selectedClub ?? (lie == .green ? .putter : suggestedClub)
        score.shots.append(Shot(start: point, club: club, lie: lie))
        apply(shots: score.shots, holeLocation: nil, to: score)
        selectedClub = nil
        selectedLie = nil
        measureTarget = nil
    }

    func undoShot() {
        guard var score = self.score(for: myID, hole: currentHole), !score.shots.isEmpty else { return }
        score.shots.removeLast()
        if score.shots.isEmpty {
            score.strokes = max(1, score.strokes - 1)
            setScore(score, for: myID)
        } else {
            apply(shots: score.shots, holeLocation: nil, to: score)
        }
    }

    /// Records where the ball dropped and finalises the hole from the tracked shots.
    func holeOut() {
        guard var score = self.score(for: myID, hole: currentHole), !score.shots.isEmpty else { return }
        // Use where you're standing if you're on or near the green, otherwise the green centre.
        var cup = holeLayout?.greenCenter
        if let position {
            if let green = holeLayout?.greenCenter {
                cup = GeoMath.distance(position, green) < 60 ? position : green
            } else {
                cup = position
            }
        }
        score.holeLocation = cup
        apply(shots: score.shots, holeLocation: cup, to: score)
        if !isLastHole {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                self?.next()
            }
        }
    }

    private func apply(shots: [Shot], holeLocation: GeoPoint?, to existing: HoleScore) {
        let derived = ShotTracking.holeScore(holeNumber: currentHole, par: par, shots: shots, holeLocation: holeLocation, layout: holeLayout)
        var score = existing
        score.shots = derived.shots
        score.strokes = derived.strokes
        score.putts = derived.putts
        score.penalties = derived.penalties
        score.sandShots = derived.sandShots
        score.holeLocation = holeLocation ?? existing.holeLocation
        if let fairway = derived.fairway { score.fairway = fairway }
        setScore(score, for: myID)
    }

    func addPenaltyToLastShot() {
        guard var score = self.score(for: myID, hole: currentHole), !score.shots.isEmpty else {
            adjustPenalties(1, for: myID)
            return
        }
        score.shots[score.shots.count - 1].penaltyStrokes += 1
        apply(shots: score.shots, holeLocation: score.holeLocation, to: score)
    }

    // MARK: - Celebrations

    private func celebrateIfNeeded(old: HoleScore?, new: HoleScore) {
        let type = new.scoreType(par: par)
        guard type.isUnderPar, old?.strokes != new.strokes else { return }
        celebrationText = new.strokes == 1 ? "Hole in one!" : "\(type.displayName)!"
        celebrationTrigger += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.snappySpring) { self?.celebrationText = nil }
        }
    }

    // MARK: - Finishing

    func finish() async {
        if let session {
            do {
                try await session.finish()
            } catch {
                app.showError(error)
            }
        }
        app.finishRound(roundID, weather: weather)
    }

    func discard() {
        app.deleteRound(roundID)
    }
}
