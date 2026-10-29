import SwiftUI
import UIKit
import GolfKit

/// A match from lobby to live play to results, switching automatically as the host
/// starts and finishes it.
struct MatchFlowView: View {
    @Environment(AppModel.self) private var app
    let matchID: UUID

    @State private var session: MatchSession?
    @State private var roundID: UUID?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let session {
                switch session.match.status {
                case .lobby:
                    LobbyView(session: session)
                        .transition(.opacity)
                case .live:
                    if let roundID {
                        LiveRoundView(roundID: roundID, session: session)
                            .transition(.move(edge: .trailing))
                    } else {
                        ProgressView().onAppear { roundID = app.startRound(for: session).id }
                    }
                case .finished:
                    if let id = roundID ?? app.library.rounds.first(where: { $0.matchID == session.id })?.id {
                        RoundSummaryView(roundID: id, session: session) { app.presentation = nil }
                    } else {
                        NavigationStack {
                            ScrollView { MatchResultsCard(session: session).padding() }
                                .toolbar { Button("Done") { app.presentation = nil } }
                        }
                    }
                }
            } else if let loadError {
                VStack(spacing: 16) {
                    EmptyStateView(title: "Couldn't open game", message: loadError, systemImage: "wifi.exclamationmark")
                    Button("Close") { app.presentation = nil }.buttonStyle(SecondaryButtonStyle()).padding(.horizontal, 60)
                }
            } else {
                ProgressView("Connecting…").controlSize(.large)
            }
        }
        .animation(.snappySpring, value: session?.match.status)
        .task { await connect() }
    }

    private func connect() async {
        if session != nil { return }
        do {
            let resolved: MatchSession
            if let existing = app.session(forMatchID: matchID) {
                resolved = existing
            } else if let game = app.library.activeGames.first(where: { $0.id == matchID }) {
                resolved = try await app.session(for: game)
            } else {
                throw MatchServiceError.notFound
            }
            if resolved.match.status != .lobby {
                roundID = app.startRound(for: resolved).id
            }
            session = resolved
            resolved.startPolling(every: resolved.match.status == .lobby ? 2.5 : 4)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Lobby

struct LobbyView: View {
    @Environment(AppModel.self) private var app
    let session: MatchSession

    @State private var isStarting = false
    @State private var showGuestPrompt = false
    @State private var guestName = ""
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            FloatingBalls().ignoresSafeArea()

            VStack(spacing: 22) {
                header
                VStack(spacing: 12) {
                    Text("ROOM CODE")
                        .font(.caption.weight(.heavy))
                        .tracking(3)
                        .opacity(0.85)
                    CodeTiles(code: session.match.code, tileSize: 66)
                    HStack(spacing: 10) {
                        ShareLink(item: session.shareMessage) {
                            Label("Invite", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                        Button {
                            UIPasteboard.general.string = session.match.code
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                    }
                    .font(.subheadline.weight(.semibold))
                }

                matchInfo
                players
                Spacer(minLength: 0)
                footer
            }
            .padding()
            .foregroundStyle(.white)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: session.snapshot.participants.count) { _, _ in app.hapticsEnabled }
        .alert("Add guest", isPresented: $showGuestPrompt) {
            TextField("Name", text: $guestName)
            Button("Add") {
                let name = guestName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { session.addGuest(name: name) }
                guestName = ""
            }
            Button("Cancel", role: .cancel) { guestName = "" }
        } message: {
            Text("For friends without the app. You'll keep their score.")
        }
    }

    private var header: some View {
        HStack {
            Button { app.presentation = nil } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.2), in: Circle())
            }
            Spacer()
            if app.isOnline {
                Label("Online", systemImage: "wifi").font(.caption.weight(.bold))
            } else {
                Label("Demo · simulated friends", systemImage: "sparkles").font(.caption.weight(.bold))
            }
            Spacer()
            Menu {
                Button("Leave game", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task {
                        if let game = app.library.activeGames.first(where: { $0.id == session.id }) {
                            await app.leave(game)
                        }
                        app.presentation = nil
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.2), in: Circle())
            }
        }
    }

    private var matchInfo: some View {
        HStack(spacing: 10) {
            InfoPill(text: session.match.course.name, systemImage: session.match.course.gameType.symbolName, tint: .white)
            InfoPill(text: session.match.format.displayName, systemImage: session.match.format.symbolName, tint: .white)
            if session.match.useHandicaps { InfoPill(text: "Net", systemImage: "plusminus", tint: .white) }
        }
        .lineLimit(1)
    }

    private var players: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Players").font(.headline)
                Text("\(session.snapshot.participants.count)")
                    .font(.headline)
                    .contentTransition(.numericText(value: Double(session.snapshot.participants.count)))
                Spacer()
                Button {
                    showGuestPrompt = true
                } label: {
                    Label("Guest", systemImage: "person.badge.plus").font(.subheadline.weight(.semibold))
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 14) {
                    ForEach(session.snapshot.participants) { player in
                        VStack(spacing: 6) {
                            AvatarView(avatar: player.avatar, size: 58, showsRing: player.id == session.myID)
                                .overlay(alignment: .topTrailing) {
                                    if player.id == session.match.hostID {
                                        Image(systemName: "crown.fill")
                                            .font(.caption)
                                            .foregroundStyle(Theme.gold)
                                            .offset(x: 4, y: -4)
                                    }
                                }
                            Text(player.id == session.myID ? "You" : player.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if player.isGuest {
                                Text("Guest").font(.caption2).opacity(0.75)
                            } else if let index = player.handicapIndex {
                                Text("HCP \(HandicapCalculator.format(index))").font(.caption2).opacity(0.75)
                            }
                        }
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 260)
        }
        .padding(16)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.playful, value: session.snapshot.participants.map(\.id))
    }

    @ViewBuilder
    private var footer: some View {
        if session.isHost {
            Button {
                Task {
                    isStarting = true
                    defer { isStarting = false }
                    do { try await session.start() } catch { app.showError(error) }
                }
            } label: {
                HStack {
                    if isStarting { ProgressView().tint(Theme.deepGreen) }
                    Text("Tee off").font(.headline)
                    Image(systemName: "figure.golf")
                }
                .foregroundStyle(Theme.deepGreen)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(.white, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(isStarting)
        } else {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Waiting for the host to tee off…").font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.white.opacity(0.15), in: Capsule())
            .phaseAnimator([0.6, 1.0]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 1.1) }
        }
    }
}

// MARK: - Leaderboard

struct MatchLeaderboardSheet: View {
    @Environment(AppModel.self) private var app
    let session: MatchSession
    @State private var selected: Participant?
    @State private var showMap = false

    private var syncStatus: String {
        let time = session.lastSynced.formatted(date: .omitted, time: .standard)
        if let error = session.lastError { return "Updated \(time) · \(error)" }
        return "Updated \(time)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.leaderboard) { entry in
                        Button { selected = entry.participant } label: {
                            LeaderboardRow(entry: entry, isMe: entry.id == session.myID, totalHoles: session.match.holeNumbers.count)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    HStack {
                        Text(session.match.format.displayName)
                        Spacer()
                        LiveBadge()
                    }
                } footer: {
                    Text(syncStatus)
                }
            }
            .animation(.snappySpring, value: session.leaderboard.map(\.id))
            .navigationTitle(session.match.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showMap = true } label: { Image(systemName: "map.fill") }
                }
            }
            .refreshable { await session.refresh() }
            .sheet(item: $selected) { player in
                ParticipantScorecardView(participant: player, match: session.match)
            }
            .navigationDestination(isPresented: $showMap) {
                CourseMapView(course: session.match.course, players: session.snapshot.participants)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    var isMe = false
    var totalHoles = 18

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.positionLabel)
                .font(.headline.monospacedDigit())
                .frame(width: 34)
                .foregroundStyle(entry.position == 1 && entry.thru > 0 ? Theme.gold : .secondary)
            AvatarView(avatar: entry.participant.avatar, size: 36, showsRing: isMe)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "\(entry.participant.name) (you)" : entry.participant.name)
                    .font(.subheadline.weight(.semibold))
                Text(progress).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.statusText)
                    .font(.headline)
                    .foregroundStyle(entry.grossToPar < 0 ? Theme.flag : .primary)
                    .contentTransition(.numericText())
                if let net = entry.netToPar, entry.courseHandicap != nil {
                    Text("Gross \(Leaderboard.formatToPar(entry.grossToPar)) · Net \(Leaderboard.formatToPar(net))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var progress: String {
        if entry.isFinished { return "Finished · \(entry.gross)" }
        if entry.thru == 0 { return entry.participant.currentHole.map { "On hole \($0)" } ?? "Not started" }
        let hole = entry.participant.currentHole.map { " · on \($0)" } ?? ""
        return "Thru \(entry.thru)\(hole)"
    }
}

/// One player's card and stats inside a match.
struct ParticipantScorecardView: View {
    @Environment(AppModel.self) private var app
    let participant: Participant
    let match: Match

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        AvatarView(avatar: participant.avatar, size: 60)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(participant.name).font(.title2.weight(.bold))
                            if let hole = participant.currentHole {
                                Label("On hole \(hole)", systemImage: "flag.fill").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ScorecardGrid(course: match.course, holes: match.holeNumbers, tee: match.tee,
                                  players: [ScorecardPlayerRow(participant: participant)], units: app.units)
                    RoundReport(round: participant.round(in: match))
                }
                .padding()
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
}
