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
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let round = app.library.inProgressRound {
                        ContinueRoundCard(round: round) { resume(round) }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if !app.library.activeGames.isEmpty {
                        ActiveGamesSection()
                    }
                    HandicapHeroCard()
                        .onTapGesture { selectedTab = .profile }
                    quickActions
                    if let weather {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Conditions", subtitle: weatherSubtitle)
                            WeatherCard(report: weather, units: app.units)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    recentRounds
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(.snappySpring, value: app.library.inProgressRoundID)
                .animation(.snappySpring, value: weather?.fetchedAt)
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Text(app.profile.name)
                    .font(.rounded(34, weight: .heavy))
            }
            Spacer()
            Button { selectedTab = .profile } label: {
                AvatarView(avatar: app.profile.avatar, size: 52)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .rotationEffect(.degrees(appeared ? 0 : -30))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 8)
        .onAppear { withAnimation(.playful.delay(0.1)) { appeared = true } }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            QuickActionTile(title: "New round", subtitle: "Solo or group", systemImage: "figure.golf", gradient: Theme.heroGradient) { showSetup = true }
            QuickActionTile(title: "Join game", subtitle: "Enter a code", systemImage: "rectangle.and.pencil.and.ellipsis", gradient: Theme.sunsetGradient) { showJoin = true }
            QuickActionTile(title: "Host match", subtitle: "Invite friends", systemImage: "person.3.fill", gradient: Theme.skyGradient) { showCreateMatch = true }
            QuickActionTile(title: "Tournament", subtitle: "Multi-round event", systemImage: "trophy.fill", gradient: Theme.goldGradient) { showCreateTournament = true }
        }
    }

    @ViewBuilder
    private var recentRounds: some View {
        let rounds = Array(app.library.completedRounds.prefix(4))
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent rounds", actionTitle: rounds.isEmpty ? nil : "Stats") { selectedTab = .stats }
            if rounds.isEmpty {
                EmptyStateView(
                    title: "No rounds yet",
                    message: "Start a round and your scores, stats and handicap build from there.",
                    systemImage: "flag.checkered",
                    actionTitle: "Start a round"
                ) { showSetup = true }
                .cardStyle()
            } else {
                VStack(spacing: 10) {
                    ForEach(rounds) { round in
                        NavigationLink(value: round) {
                            RoundRow(round: round)
                        }
                        .buttonStyle(PressableStyle())
                    }
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

struct QuickActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let gradient: LinearGradient
    let action: () -> Void
    @State private var tapped = 0

    var body: some View {
        Button {
            tapped += 1
            action()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .symbolEffect(.bounce, value: tapped)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
        }
        .buttonStyle(PressableStyle())
    }
}

struct ContinueRoundCard: View {
    @Environment(AppModel.self) private var app
    let round: Round
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white.opacity(0.2))
                    Text("\(round.nextHoleToPlay ?? round.holeNumbers.last ?? 1)")
                        .font(.rounded(22, weight: .heavy))
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        LiveBadge(text: "IN PROGRESS")
                            .colorScheme(.dark)
                    }
                    Text(round.course.name).font(.headline).lineLimit(1)
                    Text("Thru \(round.holesPlayed) · \(Leaderboard.formatToPar(round.toPar))")
                        .font(.subheadline).opacity(0.85)
                }
                Spacer()
                Image(systemName: "play.circle.fill").font(.system(size: 34))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Theme.gradient(for: round.gameType), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Games this device is part of (lobbies, live matches, tournaments).
struct ActiveGamesSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your games")
            ForEach(app.library.activeGames, id: \.id) { game in
                Button {
                    app.present(game.kind == .match ? .match(game.id) : .tournament(game.id))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: game.kind == .match ? "person.3.fill" : "trophy.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background((game.kind == .match ? Theme.skyGradient : Theme.goldGradient), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.name).font(.headline).lineLimit(1)
                            Text("Code \(JoinCode.spaced(game.code))").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .cardStyle(padding: 12)
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

struct HandicapHeroCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let golf = app.handicap(for: .golf)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Handicap index", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.9)
                Spacer()
                Text(sourceLabel(golf))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(golf.displayIndex)
                    .font(.rounded(58, weight: .heavy))
                    .contentTransition(.numericText(value: golf.index ?? 0))
                if golf.index == nil {
                    Text("\(golf.roundsUntilEstablished) more round\(golf.roundsUntilEstablished == 1 ? "" : "s") to go")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)
                }
                Spacer()
                if golf.history.count > 1 {
                    Sparkline(values: golf.history.suffix(12).map(\.index))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 90, height: 40)
                }
            }
            HStack(spacing: 8) {
                ForEach([GameType.pitchAndPutt, .miniGolf]) { type in
                    let result = app.handicap(for: type)
                    InfoPill(text: "\(type.displayName) \(result.displayIndex)", systemImage: type.symbolName, tint: .white)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.deepGreen.opacity(0.3), radius: 16, y: 8)
    }

    private func sourceLabel(_ result: HandicapResult) -> String {
        switch result.source {
        case .manual: return "MANUAL"
        case .calculated: return "WHS"
        case .notEstablished: return "PENDING"
        }
    }
}

/// A tiny line chart shape. Lower values (better handicaps) are drawn higher.
struct Sparkline: Shape {
    let values: [Double]
    var invert = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return path }
        let span = max(0.0001, hi - lo)
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let normalized = CGFloat((v - lo) / span)
            let y = invert ? rect.minY + rect.height * normalized : rect.maxY - rect.height * normalized
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

struct RoundRow: View {
    @Environment(AppModel.self) private var app
    let round: Round

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(round.date, format: .dateTime.day())
                    .font(.rounded(22, weight: .bold))
                Text(round.date, format: .dateTime.month(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(round.course.name).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: round.gameType.symbolName)
                        .foregroundStyle(Theme.tint(for: round.gameType))
                    Text(subtitle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(round.totalStrokes)")
                    .font(.rounded(24, weight: .bold))
                ToParText(toPar: round.toPar, font: .caption.weight(.bold))
            }
        }
        .foregroundStyle(.primary)
        .cardStyle(padding: 14)
    }

    private var subtitle: String {
        var parts = ["\(round.holesPlayed) holes"]
        if round.matchID != nil { parts.append("Match") }
        if round.hasShotData { parts.append("GPS") }
        if let putts = round.totalPutts { parts.append("\(putts) putts") }
        return parts.joined(separator: " · ")
    }
}
