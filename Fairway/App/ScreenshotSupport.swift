import SwiftUI
import GolfKit

/// Debug-only screenshot mode: launch with `-FairwayScreen <name>` to open the app on a
/// given screen with demo data (used by CI to capture screenshots). No effect in release.
struct ScreenshotSupport: ViewModifier {
    @Binding var tab: AppTab

    #if DEBUG
    @Environment(AppModel.self) private var app
    @State private var screen: DebugScreen?

    func body(content: Content) -> some View {
        content
            .task {
                guard let name = Self.requestedScreen else { return }
                screen = await prepare(name)
            }
            .fullScreenCover(item: $screen) { screen in
                Group {
                    if screen == .setup {
                        // Round setup brings its own navigation stack.
                        RoundSetupView()
                    } else {
                        NavigationStack { view(for: screen) }
                    }
                }
                .environment(app)
            }
    }

    static var requestedScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-FairwayScreen"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    enum DebugScreen: String, Identifiable {
        case courseDetail, courseMap, replay, headToHead, handicap, trophies, results, teamResults, rules, setup
        var id: String { rawValue }
    }

    @ViewBuilder
    private func view(for screen: DebugScreen) -> some View {
        switch screen {
        case .courseDetail:
            CourseDetailView(summary: DemoData.golfCourse.summary)
        case .courseMap:
            CourseMapView(course: DemoData.golfCourse)
        case .replay:
            if let record = app.library.matchHistory.first(where: { $0.snapshot.match.course.id == DemoData.golfCourseID }) {
                ReplayView(rounds: record.snapshot.participants.map { $0.round(in: record.snapshot.match) }, course: record.snapshot.match.course)
            }
        case .headToHead:
            if let record = HeadToHeadEngine.records(for: app.profile.id, in: app.library.matchHistory).first {
                HeadToHeadView(record: record)
            }
        case .handicap:
            HandicapView(gameType: .golf)
        case .trophies:
            TrophyCabinetView()
        case .rules:
            RulesView()
        case .setup:
            RoundSetupView()
        case .teamResults:
            if let record = app.library.matchHistory.first(where: { $0.snapshot.match.isTeamGame }) {
                ScrollView {
                    PastMatchSection(record: record)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.bottom, 32)
                }
                .background(Theme.background)
                .navigationTitle(record.snapshot.match.name)
                .navigationBarTitleDisplayMode(.inline)
            }
        case .results:
            if let record = app.library.matchHistory.first(where: { $0.snapshot.participants.count >= 4 && !$0.snapshot.match.isTeamGame }) {
                ScrollView {
                    PastMatchSection(record: record)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.bottom, 32)
                }
                .background(Theme.background)
                .navigationTitle(record.snapshot.match.name)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    /// Resets to a demo profile with sample history, then opens the requested screen.
    private func prepare(_ name: String) async -> DebugScreen? {
        if name == "onboarding" {
            app.update { $0 = GolfLibrary() }
            return nil
        }
        let profile = PlayerProfile(id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000001")!, name: "Chris", avatar: Avatar(emoji: "🦅", colorIndex: 0))
        app.update {
            $0 = GolfLibrary(profile: profile)
            $0.settings.units = name == "imperial" ? .imperial : .metric
        }
        app.loadSampleData()

        switch name {
        case "home", "imperial": tab = .home
        case "play": tab = .play
        case "compete": tab = .compete
        case "stats": tab = .stats
        case "profile": tab = .profile
        case "round":
            let course = DemoData.golfCourse
            var round = app.startSoloRound(course: course, tee: course.tees.first { $0.id == "white" }, holes: course.holes.map(\.number))
            for hole in course.holes.prefix(3) {
                round.setScore(BotGolfer.holeScore(playerID: profile.id, handicap: 12, hole: hole, gameType: .golf, layout: DemoData.golfLayout.hole(hole.number), salt: 7))
            }
            app.saveRound(round)
            app.present(.round(round.id))
        case "lobby", "match":
            if let session = try? await app.createMatch(
                name: "Saturday Skins", course: DemoData.golfCourse, tee: DemoData.golfCourse.tees.first,
                holes: DemoData.golfCourse.holes.map(\.number), format: .stableford, useHandicaps: true
            ) {
                if name == "match" {
                    try? await Task.sleep(for: .seconds(6))
                    try? await session.start()
                }
                app.present(.match(session.id))
            }
        case "tournament":
            let course = DemoData.golfCourse
            if let session = try? await app.createTournament(
                name: "Club Championship", gameType: .golf, format: .strokePlay, useHandicaps: true,
                rounds: [TournamentRound(number: 1, course: course, tee: course.tees.first), TournamentRound(number: 2, course: course, tee: course.tees.first)]
            ) {
                if let created = try? await session.startRound(1, host: app.meAsParticipant(for: .golf)) {
                    let match = MatchSession(service: app.matchService, snapshot: created, myID: profile.id)
                    app.adopt(match)
                    var me = app.meAsParticipant(for: .golf)
                    me.currentHole = 4
                    for hole in course.holes.prefix(3) {
                        me.setScore(BotGolfer.holeScore(playerID: profile.id, handicap: 12, hole: hole, gameType: .golf, layout: nil, salt: 3))
                    }
                    match.update(me)
                    try? await Task.sleep(for: .seconds(1))
                    await session.refresh()
                }
                app.present(.tournament(session.id))
            }
        case "course": return .courseDetail
        case "map": return .courseMap
        case "replay": return .replay
        case "h2h": tab = .stats; return .headToHead
        case "handicap": return .handicap
        case "trophies": return .trophies
        case "teamresults": return .teamResults
        case "rules": return .rules
        case "setup":
            // Give the location a moment to place you on the course.
            try? await Task.sleep(for: .seconds(2))
            return .setup
        case "teams":
            if let session = try? await app.createMatch(
                name: "Fourball Friday", course: DemoData.golfCourse, tee: DemoData.golfCourse.tees.first,
                holes: DemoData.golfCourse.holes.map(\.number), format: .strokePlay, useHandicaps: true,
                teamFormat: .fourBall, teamCount: 2
            ) {
                app.present(.match(session.id))
            }
        case "results": return .results
        default: break
        }
        return nil
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}
