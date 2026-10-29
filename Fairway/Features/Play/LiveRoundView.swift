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
                    VStack(alignment: .leading, spacing: 28) {
                        HoleHeader(controller: controller)
                            .id(controller.currentHole)
                            .transition(.push(from: controller.direction))
                        if controller.tracksShots {
                            mapSection
                            ShotTracker(controller: controller)
                        }
                        scoring
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                bottomBar
            }

            if let text = controller.celebrationText {
                CelebrationBanner(title: text, subtitle: "Hole \(controller.currentHole) · \(controller.course.name)", systemImage: "sparkles")
                    .padding(.top, 64)
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
        VStack(spacing: 8) {
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
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.course.name).font(.headline).lineLimit(1)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                if let weather = controller.weather {
                    WeatherChip(report: weather, units: controller.units, holeBearing: controller.holeLayout?.bearing)
                }
            }
            .padding(.horizontal, Theme.gutter)
            HoleStrip(controller: controller)
        }
        .padding(.top, 6)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var subtitle: String {
        let round = controller.round
        let toPar = round.map { Leaderboard.formatToPar($0.toPar) } ?? "E"
        let thru = round?.holesPlayed ?? 0
        if let session, session.match.isTeamGame, let team = session.myTeamPosition {
            let place = team.thru > 0 ? "\(team.positionLabel) of \(session.teamLeaderboard.count) · \(team.statusText) thru \(team.thru)" : session.match.teamFormat?.displayName ?? "Teams"
            return "\(team.team.name) team · \(place)"
        }
        if let session, let position = session.myPosition, position.thru > 0 {
            return "\(position.positionLabel) of \(session.snapshot.participants.count) · \(toPar) thru \(thru)"
        }
        if let session {
            return "\(session.snapshot.participants.count) players · \(session.match.format.displayName)"
        }
        return "\(toPar) thru \(thru)"
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let distances = controller.greenDistances {
                GreenDistancesView(distances: distances, units: controller.units, playsLike: controller.playsLike)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Hairline() }
                    .overlay(alignment: .bottom) { Hairline() }
                    .transition(.opacity)
            }
            if let layout = controller.layout, controller.holeLayout != nil {
                ZStack(alignment: .top) {
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
                    .frame(height: 340)

                    // Controls sit at the top so they never cover the Apple Maps attribution.
                    HStack {
                        Button {
                            controller.placeBallMode.toggle()
                        } label: {
                            Label(controller.placeBallMode ? "Tap map to place ball" : "Using GPS", systemImage: controller.placeBallMode ? "hand.tap" : "location.fill")
                                .font(.footnote.weight(.semibold))
                                .contentTransition(.symbolEffect(.replace))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                        .foregroundStyle(.primary)
                        Spacer()
                        Button { expandedMap = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 32, height: 32)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(PressableStyle())
                        .foregroundStyle(.primary)
                    }
                    .padding(12)
                }
                .frame(height: 340)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
                .padding(.horizontal, -Theme.gutter)
            } else if controller.tracksShots {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No hole map for this course").font(.subheadline.weight(.medium))
                        Text("OpenStreetMap hasn't mapped these holes yet. GPS still measures every shot.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "map").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var otherPlayers: [PlayerPin] {
        guard let session else { return [] }
        return session.snapshot.participants.compactMap { p in
            guard p.id != controller.myID, let location = p.lastLocation, p.currentHole == controller.currentHole else { return nil }
            return PlayerPin(id: p.id, name: p.name, avatar: p.avatar, location: location)
        }
    }

    // MARK: - Scoring

    private var scoring: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let format = controller.teamFormat, format.isOneBall {
                SectionHeader(title: "Team score", subtitle: "\(format.displayName): one ball, so one score. Anyone in the team can enter it.")
                DividedList(controller.myTeams, inset: 48) { team in
                    TeamBallRow(controller: controller, team: team)
                }
            } else if let format = controller.teamFormat {
                SectionHeader(title: "Score", subtitle: "\(format.displayName): \(format.summary.lowercased())")
                ForEach(controller.myTeams) { team in
                    TeamLabel(team: team, detail: controller.teamHoleScore(team).map { "Team score \($0)" })
                        .padding(.top, 12)
                    DividedList(controller.players.filter { team.memberIDs.contains($0.id) }, inset: 48) { player in
                        PlayerScoreRow(controller: controller, player: player, isMe: player.id == controller.myID)
                    }
                }
            } else {
                SectionHeader(title: "Score", subtitle: session == nil ? nil : "Everyone in your group")
                DividedList(controller.players, inset: 48) { player in
                    PlayerScoreRow(controller: controller, player: player, isMe: player.id == controller.myID)
                }
            }
            if session != nil {
                Hairline()
                Button {
                    showGuestPrompt = true
                } label: {
                    Label("Add a guest without the app", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.fairway)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: - Bottom bar

    private func leaderboardLabel(_ session: MatchSession) -> String {
        if session.match.isTeamGame {
            guard let team = session.myTeamPosition, team.thru > 0 else { return "Leaderboard" }
            return "\(team.positionLabel) · \(team.statusText)"
        }
        guard let position = session.myPosition, position.thru > 0 else { return "Leaderboard" }
        return "\(position.positionLabel) · \(position.statusText)"
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { controller.previous() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(CircleIconButtonStyle(size: 48))
            .disabled(controller.isFirstHole)

            if let session {
                Button { showLeaderboard = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.number")
                        Text(leaderboardLabel(session))
                            .contentTransition(.numericText())
                    }
                }
                .buttonStyle(SecondaryButtonStyle(height: 48))
            } else {
                Spacer()
            }

            if controller.isLastHole {
                Button { confirmFinish = true } label: {
                    Label("Finish", systemImage: "flag.checkered")
                }
                .buttonStyle(PrimaryButtonStyle(height: 48))
                .frame(maxWidth: 150)
            } else {
                Button { controller.next() } label: {
                    HStack(spacing: 6) {
                        Text("Hole \(controller.holeNumbers[min(controller.holeIndex + 1, controller.holeNumbers.count - 1)])")
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 48))
                .frame(maxWidth: 150)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.background)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - Hole strip

private struct HoleStrip: View {
    @Bindable var controller: LiveRoundController
    @Namespace private var selection

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(controller.holeNumbers, id: \.self) { number in
                        let score = controller.score(for: controller.myID, hole: number)
                        let isCurrent = number == controller.currentHole
                        Button { controller.go(to: number) } label: {
                            VStack(spacing: 4) {
                                Text("\(number)")
                                    .font(.eyebrow)
                                    .foregroundStyle(isCurrent ? .primary : .secondary)
                                ScoreBadge(strokes: score?.strokes, par: controller.course.hole(number)?.par ?? 4, size: 26)
                                ZStack {
                                    if isCurrent {
                                        Rectangle()
                                            .fill(Color.primary)
                                            .frame(height: 2)
                                            .matchedGeometryEffect(id: "current", in: selection)
                                    } else {
                                        Color.clear.frame(height: 2)
                                    }
                                }
                            }
                            .frame(width: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(number)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .onChange(of: controller.currentHole) { _, hole in
                withAnimation(.snappySpring) { proxy.scrollTo(hole, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(controller.currentHole, anchor: .center) }
        }
    }
}

// MARK: - Hole header

private struct HoleHeader: View {
    @Bindable var controller: LiveRoundController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("Hole")
                    Text("\(controller.currentHole)")
                        .font(.display(64, weight: .regular))
                        .contentTransition(.numericText(value: Double(controller.currentHole)))
                }
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 22) {
                    fact("Par", "\(controller.par)")
                    if let length = controller.hole?.length(for: controller.round?.tee) ?? controller.holeLayout?.length {
                        fact("Length", controller.units.distance(length))
                    }
                    if let si = controller.hole?.strokeIndex {
                        fact("S.I.", "\(si)")
                    }
                }
                .padding(.bottom, 12)
            }
            if let bearing = controller.holeLayout?.bearing, let weather = controller.weather {
                let effect = WindEffect(windSpeed: weather.current.windSpeed, windFromDirection: weather.current.windDirection, shotBearing: bearing)
                Label("\(effect.description) · \(controller.units.windSpeed(weather.current.windSpeed))", systemImage: "wind")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { controller.next() }
                if value.translation.width > 60 { controller.previous() }
            }
        )
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Eyebrow(label)
            Text(value).font(.figure(19, weight: .medium))
        }
    }
}

// MARK: - Shot tracker

private struct ShotTracker: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: LiveRoundController
    @State private var markCount = 0

    private var clubLabel: String {
        if let club = controller.selectedClub { return club.shortName }
        if let suggested = controller.suggestedClub { return suggested.shortName + "?" }
        return "Club"
    }

    private var numberedShots: [NumberedShot] {
        ShotTracking.linked(controller.shots, holeLocation: controller.score(for: controller.myID, hole: controller.currentHole)?.holeLocation)
            .enumerated()
            .map { NumberedShot(number: $0.offset + 1, shot: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Shot tracking") {
                if let accuracy = app.location.accuracy, !controller.placeBallMode {
                    Text("GPS ±\(Int(accuracy)) m").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }

            if let live = controller.liveShotDistance {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Last shot").font(.subheadline).foregroundStyle(.secondary)
                    Text(controller.units.distance(live))
                        .font(.display(34, weight: .regular))
                        .contentTransition(.numericText(value: live))
                        .animation(.snappySpring, value: Int(live))
                    Text("and counting").font(.footnote).foregroundStyle(.tertiary)
                }
                .transition(.opacity)
            }

            if !numberedShots.isEmpty {
                DividedList(numberedShots, inset: 34) { item in
                    HStack(spacing: 12) {
                        BallMarker(label: "\(item.number)", color: item.shot.isPutt ? .white : Theme.gold, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.shot.club?.displayName ?? item.shot.lie.displayName).font(.subheadline.weight(.medium))
                            Text("From the \(item.shot.lie.displayName.lowercased())").font(.caption).foregroundStyle(.secondary)
                        }
                        if item.shot.penaltyStrokes > 0 {
                            Text("+\(item.shot.penaltyStrokes)").font(.caption.weight(.bold)).foregroundStyle(Theme.flag)
                        }
                        Spacer()
                        Text(item.shot.distance.map { item.shot.isPutt ? controller.units.shortDistance($0) : controller.units.distance($0) } ?? "…")
                            .font(.figure(16, weight: .semibold))
                    }
                    .padding(.vertical, 9)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                .overlay(alignment: .bottom) { Hairline() }
            }

            HStack(spacing: 8) {
                Menu {
                    Button("Auto") { controller.selectedClub = nil }
                    ForEach(Club.allCases) { club in
                        Button(club.displayName) { controller.selectedClub = club }
                    }
                } label: {
                    optionLabel(clubLabel, systemImage: "figure.golf")
                }
                Menu {
                    Button("Auto-detect") { controller.selectedLie = nil }
                    ForEach(Lie.allCases) { lie in
                        Button(lie.displayName, systemImage: lie.symbolName) { controller.selectedLie = lie }
                    }
                } label: {
                    optionLabel(controller.selectedLie?.displayName ?? "Lie", systemImage: controller.selectedLie?.symbolName ?? "leaf")
                }
                Spacer()
                if !controller.shots.isEmpty {
                    Button { controller.undoShot() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(CircleIconButtonStyle(tint: .secondary, size: 36))
                    Button { controller.addPenaltyToLastShot() } label: { Text("+1").font(.footnote.weight(.bold)) }
                        .buttonStyle(CircleIconButtonStyle(tint: Theme.flag, size: 36))
                }
            }

            HStack(spacing: 10) {
                Button {
                    markCount += 1
                    withAnimation(.snappySpring) { controller.markShot() }
                } label: {
                    Label(controller.shots.isEmpty ? "Mark tee shot" : "Mark shot \(controller.shots.count + 1)", systemImage: "scope")
                        .contentTransition(.numericText())
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(controller.position == nil)

                if !controller.shots.isEmpty {
                    Button {
                        withAnimation(.snappySpring) { controller.holeOut() }
                    } label: {
                        Label("Holed", systemImage: "flag.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.flag, height: 52))
                    .frame(maxWidth: 130)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: markCount) { _, _ in app.hapticsEnabled }

            if controller.position == nil {
                Text(app.location.isDenied
                     ? "Location is off. Switch the map to \"Tap map to place ball\" to mark shots by hand."
                     : "Waiting for GPS… or switch the map to \"Tap map to place ball\".")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappySpring, value: controller.shots)
    }

    private func optionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.outline, lineWidth: 1))
    }
}

// MARK: - Score entry

private struct PlayerScoreRow: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: LiveRoundController
    let player: Participant
    let isMe: Bool

    var body: some View {
        let score = controller.score(for: player.id, hole: controller.currentHole)
        let par = controller.par
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AvatarView(avatar: player.avatar, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isMe ? "You" : player.name).font(.body.weight(.medium))
                        let dots = controller.strokesReceived(player)
                        if dots > 0 {
                            HStack(spacing: 2) {
                                ForEach(0..<dots, id: \.self) { _ in Circle().fill(Theme.gold).frame(width: 5, height: 5) }
                            }
                        }
                    }
                    if let score {
                        Text(score.scoreType(par: par).displayName)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.scoreColor(toPar: score.strokes - par))
                            .contentTransition(.interpolate)
                    } else {
                        Text("Par \(par) · tap + to score").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                stepper(value: score?.strokes, par: par)
            }

            if controller.course.gameType.tracksGreens {
                HStack(spacing: 18) {
                    miniStepper(title: "Putts", value: score?.putts, minus: { controller.adjustPutts(-1, for: player.id) }, plus: { controller.adjustPutts(1, for: player.id) })
                    if controller.course.gameType.tracksFairways && par >= 4 {
                        fairwayPicker(score?.fairway)
                    }
                    if isMe {
                        miniStepper(title: "Pen.", value: score?.penalties ?? 0, minus: { controller.adjustPenalties(-1, for: player.id) }, plus: { controller.adjustPenalties(1, for: player.id) })
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 48)
            }
        }
        .padding(.vertical, 14)
        .sensoryFeedback(.increase, trigger: score?.strokes ?? 0) { _, _ in app.hapticsEnabled }
    }

    private func stepper(value: Int?, par: Int) -> some View {
        HStack(spacing: 12) {
            Button { controller.adjustStrokes(-1, for: player.id) } label: { Image(systemName: "minus") }
                .buttonStyle(CircleIconButtonStyle(size: 38))
            ZStack {
                if let value {
                    ScoreBadge(strokes: value, par: par, size: 42)
                } else {
                    Text("–").font(.figure(24)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 46, height: 46)
            .pulseRing(trigger: isMe ? controller.celebrationTrigger : 0, color: Theme.flag)
            .animation(.snappySpring, value: value)
            Button { controller.adjustStrokes(1, for: player.id) } label: { Image(systemName: "plus") }
                .buttonStyle(CircleIconButtonStyle(size: 38))
        }
    }

    private func miniStepper(title: String, value: Int?, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: minus) { Image(systemName: "minus") }
                .buttonStyle(CircleIconButtonStyle(tint: .secondary, size: 26))
            VStack(spacing: 0) {
                Text(value.map { "\($0)" } ?? "–")
                    .font(.figure(15, weight: .semibold))
                    .contentTransition(.numericText(value: Double(value ?? 0)))
                Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            }
            .frame(minWidth: 30)
            Button(action: plus) { Image(systemName: "plus") }
                .buttonStyle(CircleIconButtonStyle(tint: .secondary, size: 26))
        }
    }

    private func fairwayPicker(_ current: FairwayResult?) -> some View {
        HStack(spacing: 0) {
            ForEach(FairwayResult.allCases) { result in
                let selected = current == result
                Button {
                    controller.setFairway(result, for: player.id)
                } label: {
                    Image(systemName: result.symbolName)
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 28)
                        .foregroundStyle(selected ? Theme.onAccent : .secondary)
                        .background(selected ? (result == .hit ? Theme.fairway : Theme.flag) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.outline, lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: current)
    }
}

// MARK: - Teams

/// A team's single ball in scramble and foursomes, scored once for the whole team.
private struct TeamBallRow: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: LiveRoundController
    let team: Team

    var body: some View {
        let score = controller.teamBallScore(team)
        let par = controller.par
        let members = controller.members(of: team)
        HStack(spacing: 12) {
            TeamAvatars(team: team, members: members, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(team.name) team").font(.body.weight(.medium))
                    let dots = controller.teamStrokesReceived(team)
                    if dots > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<dots, id: \.self) { _ in Circle().fill(Theme.gold).frame(width: 5, height: 5) }
                        }
                    }
                }
                if let score {
                    Text(score.scoreType(par: par).displayName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.scoreColor(toPar: score.strokes - par))
                        .contentTransition(.interpolate)
                } else {
                    Text(members.map(\.name).joined(separator: " & ")).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Button { controller.adjustTeamStrokes(-1, team: team) } label: { Image(systemName: "minus") }
                    .buttonStyle(CircleIconButtonStyle(size: 38))
                ZStack {
                    if let score {
                        ScoreBadge(strokes: score.strokes, par: par, size: 42)
                    } else {
                        Text("–").font(.figure(24)).foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 46, height: 46)
                .pulseRing(trigger: controller.celebrationTrigger, color: Theme.flag)
                .animation(.snappySpring, value: score?.strokes)
                Button { controller.adjustTeamStrokes(1, team: team) } label: { Image(systemName: "plus") }
                    .buttonStyle(CircleIconButtonStyle(size: 38))
            }
        }
        .padding(.vertical, 14)
        .sensoryFeedback(.increase, trigger: score?.strokes ?? 0) { _, _ in app.hapticsEnabled }
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
                .padding(Theme.gutter)
            }
            .background(Theme.background)
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
                        .frame(width: 240)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .foregroundStyle(.primary)
            }
            .padding()

            VStack {
                Spacer()
                Text(controller.placeBallMode ? "Tap to place your ball" : "Tap anywhere to measure a layup")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 30)
            }
        }
    }
}
