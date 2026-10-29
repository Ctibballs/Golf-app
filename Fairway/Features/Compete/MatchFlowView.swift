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
                            ScrollView {
                                let model = ResultsCardModel(snapshot: session.snapshot)
                                VStack(alignment: .leading, spacing: 16) {
                                    ResultsCard(model: model, units: app.units)
                                    ShareScorecardButton(model: model, units: app.units)
                                        .buttonStyle(SecondaryButtonStyle(tint: Theme.fairway))
                                }
                                .padding(.horizontal, Theme.gutter)
                            }
                            .background(Theme.background)
                            .toolbar { Button("Done") { app.presentation = nil } }
                        }
                    }
                }
            } else if let loadError {
                VStack(spacing: 12) {
                    EmptyStateView(title: "Couldn't open game", message: loadError, systemImage: "wifi.exclamationmark")
                    if let round = app.library.rounds.first(where: { $0.matchID == matchID && !$0.isComplete }) {
                        // Offline demo games don't survive a relaunch; your own card does.
                        Button("Keep scoring on this phone") { app.present(.round(round.id)) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    if let game = app.library.activeGames.first(where: { $0.id == matchID }) {
                        Button("Remove this game", role: .destructive) {
                            Task {
                                await app.leave(game)
                                app.presentation = nil
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle(tint: Theme.flag))
                    }
                    Button("Close") { app.presentation = nil }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 40)
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
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    codeBlock
                    players
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            footer
        }
        .background(Theme.background)
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
            }
            .buttonStyle(CircleIconButtonStyle(size: 36))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(app.isOnline ? Theme.fairway : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                Text(app.isOnline ? "Online" : "Demo · simulated friends").font(.footnote).foregroundStyle(.secondary)
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 8)
    }

    private var codeBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Match lobby")
                Text(session.match.name).font(.display(30)).lineLimit(2)
                Text(matchDetails).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Room code")
                CodeTiles(code: session.match.code, tileSize: 62)
            }
            .padding(.top, 6)
            HStack(spacing: 10) {
                ShareLink(item: session.shareMessage) {
                    Label("Invite", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle(height: 44))
                Button {
                    UIPasteboard.general.string = session.match.code
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(SecondaryButtonStyle(height: 44))
                .sensoryFeedback(.success, trigger: copied)
            }
        }
    }

    private var matchDetails: String {
        var parts = [session.match.course.name, session.match.format.displayName]
        if session.match.useHandicaps { parts.append("Net") }
        return parts.joined(separator: " · ")
    }

    private var players: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Players · \(session.snapshot.participants.count)", actionTitle: "Add guest") { showGuestPrompt = true }
            DividedList(session.snapshot.participants, inset: 50) { player in
                HStack(spacing: 14) {
                    AvatarView(avatar: player.avatar, size: 36, showsRing: player.id == session.myID)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.id == session.myID ? "\(player.name) (you)" : player.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(playerDetail(player)).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if player.id == session.match.hostID {
                        Eyebrow("Host", color: Theme.gold)
                    }
                }
                .padding(.vertical, 10)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
            .animation(.snappySpring, value: session.snapshot.participants.map(\.id))
        }
    }

    private func playerDetail(_ player: Participant) -> String {
        if player.isGuest { return "Guest" }
        if let index = player.handicapIndex { return "Handicap \(HandicapCalculator.format(index))" }
        return session.match.useHandicaps ? "No handicap · plays off scratch" : "No handicap"
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            if session.isHost {
                Button {
                    Task {
                        isStarting = true
                        defer { isStarting = false }
                        do { try await session.start() } catch { app.showError(error) }
                    }
                } label: {
                    HStack {
                        if isStarting { ProgressView().tint(Theme.onAccent) }
                        Text("Tee off")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isStarting)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for the host to tee off").font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .phaseAnimator([0.55, 1.0]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 1.1) }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Hairline() }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: session.match.format.displayName, subtitle: syncStatus) {
                        LiveBadge()
                    }
                    DividedList(session.leaderboard, inset: 46) { entry in
                        Button { selected = entry.participant } label: {
                            LeaderboardRow(entry: entry, isMe: entry.id == session.myID, totalHoles: session.match.holeNumbers.count)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .animation(.snappySpring, value: session.leaderboard.map(\.id))
            }
            .background(Theme.background)
            .navigationTitle(session.match.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showMap = true } label: { Image(systemName: "map") }
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
                .font(.figure(15, weight: .semibold))
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(entry.position == 1 && entry.thru > 0 ? Theme.gold : .secondary)
            AvatarView(avatar: entry.participant.avatar, size: 34, showsRing: isMe)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "\(entry.participant.name) (you)" : entry.participant.name)
                    .font(.body.weight(.medium))
                Text(progress).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.statusText)
                    .font(.figure(18, weight: .semibold))
                    .foregroundStyle(entry.grossToPar < 0 ? Theme.flag : .primary)
                    .contentTransition(.numericText())
                if let net = entry.netToPar, entry.courseHandicap != nil {
                    Text("Gross \(Leaderboard.formatToPar(entry.grossToPar)) · Net \(Leaderboard.formatToPar(net))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
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
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    HStack(spacing: 14) {
                        AvatarView(avatar: participant.avatar, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(participant.name).font(.display(26))
                            if let hole = participant.currentHole {
                                Label("On hole \(hole)", systemImage: "flag").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ScorecardGrid(course: match.course, holes: match.holeNumbers, tee: match.tee,
                                  players: [ScorecardPlayerRow(participant: participant)], units: app.units)
                    RoundReport(round: participant.round(in: match))
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
}
