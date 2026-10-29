import SwiftUI
import GolfKit

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Binding var selectedTab: AppTab

    @State private var weather: WeatherReport?
    @State private var showSetup = false
    @State private var showJoin = false
    @State private var showCreateMatch = false
    @State private var showCreateTournament = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    header.reveal(0)
                    if let round = app.library.inProgressRound {
                        ContinueRoundRow(round: round) { resume(round) }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    HandicapSummary { selectedTab = .profile }
                        .reveal(1)
                    actions.reveal(2)
                    if !app.library.activeGames.isEmpty {
                        ActiveGamesSection()
                    }
                    if let weather {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Conditions", subtitle: weatherSubtitle)
                            WeatherPanel(report: weather, units: app.units)
                        }
                        .transition(.opacity)
                    }
                    recentRounds
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .animation(.snappySpring, value: app.library.inProgressRoundID)
                .animation(.gentle, value: weather?.fetchedAt)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await loadWeather() }
            .task { await loadWeather() }
            .sheet(isPresented: $showSetup) { RoundSetupView() }
            .sheet(isPresented: $showJoin) { JoinGameView() }
            .sheet(isPresented: $showCreateMatch) { CreateMatchView() }
            .sheet(isPresented: $showCreateTournament) { CreateTournamentView() }
            .navigationDestination(for: Round.self) { RoundDetailView(roundID: $0.id) }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                Text("\(greeting),\n\(app.profile.name)")
                    .font(.display(32))
                    .lineSpacing(2)
            }
            Spacer()
            Button { selectedTab = .profile } label: {
                AvatarView(avatar: app.profile.avatar, size: 44)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 12)
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Button { showSetup = true } label: {
                HStack {
                    Image(systemName: "figure.golf")
                    Text("Start a round")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(.horizontal, 18)
            }
            .buttonStyle(PrimaryButtonStyle(height: 56))

            HStack(spacing: 0) {
                ActionCell(title: "Join", subtitle: "Enter a code", systemImage: "number") { showJoin = true }
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                ActionCell(title: "Host", subtitle: "Play friends", systemImage: "person.2") { showCreateMatch = true }
                    .padding(.leading, 14)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                ActionCell(title: "Tournament", subtitle: "Multi-round", systemImage: "trophy") { showCreateTournament = true }
                    .padding(.leading, 14)
            }
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    @ViewBuilder
    private var recentRounds: some View {
        let rounds = Array(app.library.completedRounds.prefix(5))
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Recent rounds", actionTitle: rounds.isEmpty ? nil : "All stats") { selectedTab = .stats }
            if rounds.isEmpty {
                EmptyStateView(
                    title: "No rounds yet",
                    message: "Start a round and your scores, stats and handicap build from there.",
                    systemImage: "flag",
                    actionTitle: "Start a round"
                ) { showSetup = true }
            } else {
                DividedList(rounds) { round in
                    NavigationLink(value: round) { RoundRow(round: round) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }

    // MARK: - Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var weatherSubtitle: String {
        if app.location.point != nil { return "At your location" }
        return app.library.completedRounds.first.map { "At \($0.course.name)" } ?? "Demo course"
    }

    private func loadWeather() async {
        app.location.requestOneShot()
        let point = app.location.point
            ?? app.library.completedRounds.first?.course.location
            ?? DemoData.golfCourse.location
        guard let point else { return }
        weather = await app.weather(at: point)
    }

    private func resume(_ round: Round) {
        if let matchID = round.matchID {
            app.present(.match(matchID))
        } else {
            app.present(.round(round.id))
        }
    }
}

// MARK: - Components

/// One of the secondary actions under the main button.
struct ActionCell: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
    @State private var tapped = 0

    var body: some View {
        Button {
            tapped += 1
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.fairway)
                    .symbolEffect(.bounce, value: tapped)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// A round in progress, marked with an accent rule down the side.
struct ContinueRoundRow: View {
    let round: Round
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    LiveBadge(text: "In progress")
                    Text(round.course.name).font(.headline).lineLimit(1)
                    Text("Hole \(round.nextHoleToPlay ?? round.holeNumbers.last ?? 1) · thru \(round.holesPlayed) · \(Leaderboard.formatToPar(round.toPar))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Resume")
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.fairway)
            }
            .foregroundStyle(.primary)
            .padding(.leading, 16)
            .padding(.vertical, 4)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.flag).frame(width: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Games this device is part of (lobbies, live matches, tournaments).
struct ActiveGamesSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Your games")
            DividedList(app.library.activeGames, inset: 38) { game in
                Button {
                    app.present(game.kind == .match ? .match(game.id) : .tournament(game.id))
                } label: {
                    NavigationRowLabel(
                        title: game.name,
                        subtitle: "\(game.kind == .match ? "Match" : "Tournament") · code \(JoinCode.spaced(game.code))",
                        systemImage: game.kind == .match ? "person.2" : "trophy"
                    )
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button("Leave game", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        Task { await app.leave(game) }
                    }
                }
            }
        }
    }
}

/// The handicap index set large, with its recent trend.
struct HandicapSummary: View {
    @Environment(AppModel.self) private var app
    var action: () -> Void = {}

    var body: some View {
        let golf = app.handicap(for: .golf)
        let history = golf.history.suffix(12).map(\.index)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow("Handicap index")
                    Spacer()
                    Eyebrow(sourceLabel(golf))
                }
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(golf.displayIndex)
                        .font(.display(68, weight: .regular))
                        .contentTransition(.numericText(value: golf.index ?? 0))
                    if let change = change(history) {
                        HStack(spacing: 3) {
                            Image(systemName: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                            Text(String(format: "%.1f", abs(change)))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(change <= 0 ? Theme.fairway : Theme.flag)
                    }
                    Spacer(minLength: 0)
                    if history.count > 1 {
                        AnimatedSparkline(values: history)
                            .frame(width: 96, height: 36)
                            .padding(.bottom, 10)
                    }
                }
                if golf.index == nil {
                    Text("\(golf.roundsUntilEstablished) more round\(golf.roundsUntilEstablished == 1 ? "" : "s") to establish your index")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 28) {
                    ForEach([GameType.pitchAndPutt, .miniGolf]) { type in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName).font(.caption).foregroundStyle(.secondary)
                            Text(app.handicap(for: type).displayIndex).font(.figure(17, weight: .semibold))
                        }
                    }
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    /// Change across the recent history (negative is an improvement).
    private func change(_ values: [Double]) -> Double? {
        guard let first = values.first, let last = values.last, values.count > 1 else { return nil }
        let delta = last - first
        return abs(delta) >= 0.05 ? delta : nil
    }

    private func sourceLabel(_ result: HandicapResult) -> String {
        switch result.source {
        case .manual: return "Manual"
        case .calculated: return "WHS · \(result.eligibleRounds) scores"
        case .notEstablished: return "Pending"
        }
    }
}

struct RoundRow: View {
    let round: Round

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(round.date, format: .dateTime.day())
                    .font(.figure(20, weight: .medium))
                Text(round.date, format: .dateTime.month(.abbreviated))
                    .font(.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(round.course.name).font(.body.weight(.medium)).lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(round.totalStrokes)")
                    .font(.figure(20, weight: .semibold))
                ToParText(toPar: round.toPar, font: .footnote.weight(.medium))
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = [round.gameType.displayName, "\(round.holesPlayed) holes"]
        if round.matchID != nil { parts.append("Match") }
        if round.hasShotData { parts.append("GPS") }
        return parts.joined(separator: " · ")
    }
}
