import SwiftUI
import GolfKit

/// The on-course screen: hole info, distances and map, GPS shot tracking, and score entry
/// for you (and any guests), with a live leaderboard in matches.
struct LiveRoundView: View {
    @Environment(AppModel.self) private var app
    let roundID: UUID
    let session: MatchSession?

    @State private var controller: LiveRoundController?
    @State private var showSummary = false

    var body: some View {
        Group {
            if showSummary {
                RoundSummaryView(roundID: roundID, session: session) { app.presentation = nil }
                    .transition(.move(edge: .bottom))
            } else if let controller {
                LiveRoundContent(controller: controller, session: session) {
                    withAnimation(.snappySpring) { showSummary = true }
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            guard controller == nil else { return }
            if app.round(roundID) == nil, let session { app.startRound(for: session) }
            let c = LiveRoundController(app: app, roundID: roundID, session: session)
            controller = c
            await c.load()
        }
        .onDisappear { controller?.unload() }
    }
}

private struct LiveRoundContent: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: LiveRoundController
    let session: MatchSession?
    let onFinished: () -> Void

    @State private var showLeaderboard = false
    @State private var showScorecard = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var showGuestPrompt = false
    @State private var guestName = ""
    @State private var expandedMap = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 16) {
                        HoleHeaderCard(controller: controller)
                            .id(controller.currentHole)
                            .transition(.push(from: controller.direction))
                        if controller.tracksShots {
                            mapSection
                            ShotTrackerCard(controller: controller)
                        }
                        ForEach(controller.players) { player in
                            PlayerScoreCard(controller: controller, player: player, isMe: player.id == controller.myID)
                        }
                        if session != nil {
                            Button {
                                showGuestPrompt = true
                            } label: {
                                Label("Add a guest without the app", systemImage: "person.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                bottomBar
            }

            ConfettiView(trigger: controller.celebrationTrigger)
                .ignoresSafeArea()
            if let text = controller.celebrationText {
                CelebrationBanner(title: text, subtitle: "Hole \(controller.currentHole) · \(controller.course.name)", systemImage: "sparkles")
                    .padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappySpring, value: controller.currentHole)
        .animation(.snappySpring, value: controller.celebrationText)
        .sensoryFeedback(.success, trigger: controller.celebrationTrigger) { _, _ in app.hapticsEnabled }
        .sensoryFeedback(.selection, trigger: controller.currentHole) { _, _ in app.hapticsEnabled }
        .onChange(of: app.location.location) { controller.locationDidChange() }
        .sheet(isPresented: $showLeaderboard) {
            if let session { MatchLeaderboardSheet(session: session) }
        }
        .sheet(isPresented: $showScorecard) {
            LiveScorecardSheet(controller: controller, session: session)
        }
        .fullScreenCover(isPresented: $expandedMap) {
            if let layout = controller.layout {
                ExpandedHoleMap(controller: controller, layout: layout)
            }
        }
        .confirmationDialog("Finish round?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish and save") {
                Task {
                    await controller.finish()
                    onFinished()
                }
            }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text(controller.allHolesScored ? "All holes are scored." : "Some holes have no score yet. Rounds of nine or more holes still count.")
        }
        .confirmationDialog("Discard this round?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard round", role: .destructive) {
                controller.discard()
                app.presentation = nil
            }
        }
        .alert("Add guest", isPresented: $showGuestPrompt) {
            TextField("Name", text: $guestName)
            Button("Add") {
                let name = guestName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { session?.addGuest(name: name) }
                guestName = ""
            }
            Button("Cancel", role: .cancel) { guestName = "" }
        } message: {
            Text("You'll keep their score on this phone.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Menu {
                    Button("Scorecard", systemImage: "tablecells") { showScorecard = true }
                    Button("Finish round", systemImage: "flag.checkered") { confirmFinish = true }
                    Button("Minimise", systemImage: "chevron.down") { app.presentation = nil }
                    if session == nil {
                        Button("Discard round", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(Theme.card, in: Circle())
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.course.name).font(.headline).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let weather = controller.weather {
                    WeatherChip(report: weather, units: controller.units, holeBearing: controller.holeLayout?.bearing)
                }
            }
            .padding(.horizontal)
            HoleStrip(controller: controller)
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var subtitle: String {
        let round = controller.round
        let toPar = round.map { Leaderboard.formatToPar($0.toPar) } ?? "E"
        let thru = round?.holesPlayed ?? 0
        if let session, let position = session.myPosition {
            return "\(position.positionLabel) of \(session.snapshot.participants.count) · \(toPar) thru \(thru)"
        }
        return "\(toPar) thru \(thru)"
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        if let layout = controller.layout, controller.holeLayout != nil {
            ZStack(alignment: .topLeading) {
                HoleMapView(
                    course: controller.course,
                    layout: layout,
                    holeNumber: controller.currentHole,
                    shots: controller.shots,
                    holeLocation: controller.score(for: controller.myID, hole: controller.currentHole)?.holeLocation,
                    position: controller.position,
                    others: otherPlayers,
                    target: $controller.measureTarget,
                    units: controller.units,
                    onPlaceBall: controller.placeBallMode ? { controller.manualBall = $0 } : nil
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                if let distances = controller.greenDistances {
                    GreenDistancesView(distances: distances, units: controller.units, playsLike: controller.playsLike)
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(10)
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    HStack {
                        Toggle(isOn: $controller.placeBallMode) {
                            Label(controller.placeBallMode ? "Tap map to place ball" : "Using GPS", systemImage: controller.placeBallMode ? "hand.tap.fill" : "location.fill")
                                .font(.caption.weight(.bold))
                        }
                        .toggleStyle(.button)
                        .tint(.white)
                        .buttonStyle(.bordered)
                        .background(.black.opacity(0.35), in: Capsule())
                        Spacer()
                        Button { expandedMap = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                    }
                    .padding(10)
                }
            }
            .frame(height: 320)
        } else if controller.tracksShots {
            NoMapCard(controller: controller)
        }
    }

    private var otherPlayers: [PlayerPin] {
        guard let session else { return [] }
        return session.snapshot.participants.compactMap { p in
            guard p.id != controller.myID, let location = p.lastLocation, p.currentHole == controller.currentHole else { return nil }
            return PlayerPin(id: p.id, name: p.name, avatar: p.avatar, location: location)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { controller.previous() } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 50, height: 50)
            }
            .buttonStyle(CircleIconButtonStyle(size: 50))
            .disabled(controller.isFirstHole)
            .opacity(controller.isFirstHole ? 0.4 : 1)

            if let session {
                Button { showLeaderboard = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.number")
                        Text(session.myPosition.map { "\($0.positionLabel) · \($0.statusText)" } ?? "Leaderboard")
                            .contentTransition(.numericText())
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.card, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .foregroundStyle(.primary)
            } else {
                Spacer()
            }

            if controller.isLastHole {
                Button { confirmFinish = true } label: {
                    Label("Finish", systemImage: "flag.checkered")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(Theme.heroGradient, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            } else {
                Button { controller.next() } label: {
                    HStack(spacing: 6) {
                        Text("Hole \(controller.holeNumbers[min(controller.holeIndex + 1, controller.holeNumbers.count - 1)])")
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(Theme.heroGradient, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}

// MARK: - Hole strip

private struct HoleStrip: View {
    @Bindable var controller: LiveRoundController
    @Namespace private var selection

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(controller.holeNumbers, id: \.self) { number in
                        let score = controller.score(for: controller.myID, hole: number)
                        Button { controller.go(to: number) } label: {
                            VStack(spacing: 3) {
                                Text("\(number)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                ScoreBadge(strokes: score?.strokes, par: controller.course.hole(number)?.par ?? 4, size: 26)
                            }
                            .frame(width: 36, height: 52)
                            .background {
                                if number == controller.currentHole {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.fairway.opacity(0.18))
                                        .matchedGeometryEffect(id: "current", in: selection)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(number)
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: controller.currentHole) { _, hole in
                withAnimation(.snappySpring) { proxy.scrollTo(hole, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(controller.currentHole, anchor: .center) }
        }
    }
}

// MARK: - Hole header

private struct HoleHeaderCard: View {
    @Bindable var controller: LiveRoundController

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 0) {
                Text("HOLE").font(.caption2.weight(.heavy)).opacity(0.8)
                Text("\(controller.currentHole)")
                    .font(.rounded(54, weight: .heavy))
                    .contentTransition(.numericText(value: Double(controller.currentHole)))
            }
            .frame(width: 92)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    InfoPill(text: "Par \(controller.par)", tint: .white)
                    if let si = controller.hole?.strokeIndex { InfoPill(text: "S.I. \(si)", tint: .white) }
                }
                if let length = controller.hole?.length(for: controller.round?.tee) ?? controller.holeLayout?.length {
                    Text(controller.units.distance(length))
                        .font(.title2.weight(.bold))
                }
                if let bearing = controller.holeLayout?.bearing, let weather = controller.weather {
                    let effect = WindEffect(windSpeed: weather.current.windSpeed, windFromDirection: weather.current.windDirection, shotBearing: bearing)
                    Label("\(effect.description) · \(controller.units.windSpeed(weather.current.windSpeed))", systemImage: "wind")
                        .font(.caption.weight(.semibold))
                        .opacity(0.9)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Theme.gradient(for: controller.course.gameType), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.deepGreen.opacity(0.25), radius: 12, y: 6)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { controller.next() }
                if value.translation.width > 60 { controller.previous() }
            }
        )
    }
}

/// When a course has no mapped geometry, GPS still measures shot lengths.
private struct NoMapCard: View {
    @Bindable var controller: LiveRoundController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(Theme.water)
            VStack(alignment: .leading, spacing: 2) {
                Text("No hole map for this course").font(.subheadline.weight(.semibold))
                Text("OpenStreetMap hasn't mapped these holes yet. GPS still measures every shot.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

// MARK: - Shot tracker

private struct ShotTrackerCard: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: LiveRoundController
    @State private var markCount = 0

    private var clubLabel: String {
        if let club = controller.selectedClub { return club.shortName }
        if let suggested = controller.suggestedClub { return suggested.shortName + "?" }
        return "Club"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Shot tracking", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.headline)
                Spacer()
                if let accuracy = app.location.accuracy, !controller.placeBallMode {
                    Text("GPS ±\(Int(accuracy)) m").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }

            if let live = controller.liveShotDistance {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Last shot").font(.subheadline).foregroundStyle(.secondary)
                    Text(controller.units.distance(live))
                        .font(.rounded(30, weight: .heavy))
                        .contentTransition(.numericText(value: live))
                        .animation(.snappySpring, value: Int(live))
                    Text("and counting").font(.caption).foregroundStyle(.tertiary)
                }
                .transition(.opacity)
            }

            if !controller.shots.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(ShotTracking.linked(controller.shots, holeLocation: controller.score(for: controller.myID, hole: controller.currentHole)?.holeLocation).enumerated()), id: \.element.id) { index, shot in
                        HStack(spacing: 10) {
                            BallMarker(label: "\(index + 1)", color: shot.isPutt ? .white : Theme.gold, size: 22)
                            Text(shot.club?.displayName ?? shot.lie.displayName).font(.subheadline.weight(.semibold))
                            Text("from \(shot.lie.displayName.lowercased())").font(.caption).foregroundStyle(.secondary)
                            if shot.penaltyStrokes > 0 {
                                InfoPill(text: "+\(shot.penaltyStrokes)", tint: Theme.flag)
                            }
                            Spacer()
                            Text(shot.distance.map { shot.isPutt ? controller.units.shortDistance($0) : controller.units.distance($0) } ?? "…")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }

            HStack(spacing: 8) {
                Menu {
                    Button("Auto") { controller.selectedClub = nil }
                    ForEach(Club.allCases) { club in
                        Button(club.displayName) { controller.selectedClub = club }
                    }
                } label: {
                    Label(clubLabel, systemImage: "figure.golf")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                Menu {
                    Button("Auto-detect") { controller.selectedLie = nil }
                    ForEach(Lie.allCases) { lie in
                        Button(lie.displayName, systemImage: lie.symbolName) { controller.selectedLie = lie }
                    }
                } label: {
                    Label(controller.selectedLie?.displayName ?? "Lie", systemImage: controller.selectedLie?.symbolName ?? "leaf")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                Spacer()
                if !controller.shots.isEmpty {
                    Button { controller.undoShot() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(CircleIconButtonStyle(tint: .secondary, size: 40))
                    Button { controller.addPenaltyToLastShot() } label: { Text("+1").font(.subheadline.weight(.heavy)) }
                        .buttonStyle(CircleIconButtonStyle(tint: Theme.flag, size: 40))
                }
            }
            .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Button {
                    markCount += 1
                    withAnimation(.snappySpring) { controller.markShot() }
                } label: {
                    Label(controller.shots.isEmpty ? "Mark tee shot" : "Mark shot \(controller.shots.count + 1)", systemImage: "scope")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(controller.position == nil)

                if !controller.shots.isEmpty {
                    Button {
                        withAnimation(.snappySpring) { controller.holeOut() }
                    } label: {
                        Label("Holed", systemImage: "flag.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(gradient: Theme.sunsetGradient))
                    .frame(maxWidth: 140)
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: markCount) { _, _ in app.hapticsEnabled }

            if controller.position == nil {
                Text(app.location.isDenied
                     ? "Location is off. Turn on \"Tap map to place ball\" to mark shots by hand."
                     : "Waiting for GPS… or switch to \"Tap map to place ball\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .animation(.snappySpring, value: controller.shots)
    }
}

// MARK: - Score entry

private struct PlayerScoreCard: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: LiveRoundController
    let player: Participant
    let isMe: Bool

    var body: some View {
        let score = controller.score(for: player.id, hole: controller.currentHole)
        let par = controller.par
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(avatar: player.avatar, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isMe ? "You" : player.name).font(.headline)
                        let dots = controller.strokesReceived(player)
                        if dots > 0 {
                            HStack(spacing: 2) {
                                ForEach(0..<dots, id: \.self) { _ in Circle().fill(Theme.gold).frame(width: 6, height: 6) }
                            }
                        }
                    }
                    if let score {
                        Text(score.scoreType(par: par).displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.scoreColor(toPar: score.strokes - par))
                            .contentTransition(.interpolate)
                    } else {
                        Text("Tap + or − to score").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                stepper(value: score?.strokes, par: par)
            }

            if controller.course.gameType.tracksGreens {
                HStack(spacing: 10) {
                    miniStepper(title: "Putts", value: score?.putts, minus: { controller.adjustPutts(-1, for: player.id) }, plus: { controller.adjustPutts(1, for: player.id) })
                    if controller.course.gameType.tracksFairways && par >= 4 {
                        fairwayPicker(score?.fairway)
                    }
                    if isMe {
                        miniStepper(title: "Pen.", value: score?.penalties ?? 0, minus: { controller.adjustPenalties(-1, for: player.id) }, plus: { controller.adjustPenalties(1, for: player.id) })
                    }
                }
            }
        }
        .cardStyle()
        .sensoryFeedback(.increase, trigger: score?.strokes ?? 0) { _, _ in app.hapticsEnabled }
    }

    private func stepper(value: Int?, par: Int) -> some View {
        HStack(spacing: 10) {
            Button { controller.adjustStrokes(-1, for: player.id) } label: { Image(systemName: "minus") }
                .buttonStyle(CircleIconButtonStyle(size: 42))
            ZStack {
                if let value {
                    ScoreBadge(strokes: value, par: par, size: 52)
                } else {
                    Text("–").font(.rounded(30, weight: .bold)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 58)
            .animation(.playful, value: value)
            Button { controller.adjustStrokes(1, for: player.id) } label: { Image(systemName: "plus") }
                .buttonStyle(CircleIconButtonStyle(size: 42))
        }
    }

    private func miniStepper(title: String, value: Int?, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: minus) { Image(systemName: "minus").font(.caption.weight(.bold)) }
                .buttonStyle(CircleIconButtonStyle(tint: .secondary, size: 28))
            VStack(spacing: 0) {
                Text(value.map { "\($0)" } ?? "–")
                    .font(.headline)
                    .contentTransition(.numericText(value: Double(value ?? 0)))
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 34)
            Button(action: plus) { Image(systemName: "plus").font(.caption.weight(.bold)) }
                .buttonStyle(CircleIconButtonStyle(tint: .secondary, size: 28))
        }
        .padding(6)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }

    private func fairwayPicker(_ current: FairwayResult?) -> some View {
        HStack(spacing: 4) {
            ForEach(FairwayResult.allCases) { result in
                Button {
                    controller.setFairway(result, for: player.id)
                } label: {
                    Image(systemName: result.symbolName)
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(current == result ? .white : .secondary)
                        .background(current == result ? (result == .hit ? Theme.fairway : Theme.flag) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .animation(.snappySpring, value: current)
    }
}

// MARK: - Sheets

private struct LiveScorecardSheet: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: LiveRoundController
    let session: MatchSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                ScorecardGrid(
                    course: controller.course,
                    holes: controller.holeNumbers,
                    tee: controller.round?.tee,
                    players: rows,
                    highlightedHole: controller.currentHole,
                    units: controller.units
                )
                .padding()
            }
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var rows: [ScorecardPlayerRow] {
        if let session { return session.snapshot.participants.map(ScorecardPlayerRow.init(participant:)) }
        guard let round = controller.round else { return [] }
        return [ScorecardPlayerRow(round: round, avatar: app.profile.avatar)]
    }
}

/// Full-screen hole map for measuring layups.
private struct ExpandedHoleMap: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: LiveRoundController
    let layout: CourseLayout

    var body: some View {
        ZStack(alignment: .top) {
            HoleMapView(
                course: controller.course,
                layout: layout,
                holeNumber: controller.currentHole,
                shots: controller.shots,
                position: controller.position,
                target: $controller.measureTarget,
                units: controller.units,
                onPlaceBall: controller.placeBallMode ? { controller.manualBall = $0 } : nil
            )
            .ignoresSafeArea()

            HStack(alignment: .top) {
                if let distances = controller.greenDistances {
                    GreenDistancesView(distances: distances, units: controller.units, playsLike: controller.playsLike)
                        .foregroundStyle(.white)
                        .frame(width: 230)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                }
            }
            .padding()

            VStack {
                Spacer()
                Text(controller.placeBallMode ? "Tap to place your ball" : "Tap anywhere to measure a layup")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 30)
            }
        }
    }
}
