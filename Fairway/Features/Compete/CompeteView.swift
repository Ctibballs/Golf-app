import SwiftUI
import GolfKit

/// The Compete tab: host or join matches, run tournaments, and look back at past games.
struct CompeteView: View {
    @Environment(AppModel.self) private var app
    @State private var showJoin = false
    @State private var showCreateMatch = false
    @State private var showCreateTournament = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heroButtons
                    OnlineStatusCard()
                    if !app.library.activeGames.isEmpty {
                        ActiveGamesSection()
                    }
                    tournamentsSection
                    pastMatchesSection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Compete")
            .sheet(isPresented: $showJoin) { JoinGameView() }
            .sheet(isPresented: $showCreateMatch) { CreateMatchView() }
            .sheet(isPresented: $showCreateTournament) { CreateTournamentView() }
        }
    }

    private var heroButtons: some View {
        HStack(spacing: 12) {
            Button { showCreateMatch = true } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "person.3.sequence.fill").font(.title)
                    Text("Host a match").font(.headline)
                    Text("Get a four-letter code").font(.caption).opacity(0.85)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
                .padding(16)
                .foregroundStyle(.white)
                .background(Theme.skyGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(PressableStyle())

            Button { showJoin = true } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 3) {
                        ForEach(Array("JOIN"), id: \.self) { letter in
                            Text(String(letter))
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.flag)
                                .frame(width: 22, height: 26)
                                .background(.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    Text("Join with code").font(.headline)
                    Text("Matches & tournaments").font(.caption).opacity(0.85)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
                .padding(16)
                .foregroundStyle(.white)
                .background(Theme.sunsetGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var tournamentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tournaments", actionTitle: "New") { showCreateTournament = true }
            if app.library.tournaments.isEmpty {
                EmptyStateView(
                    title: "Run your own major",
                    message: "Multi-round events with a live leaderboard, every player's current hole and detailed stats.",
                    systemImage: "trophy",
                    actionTitle: "Create tournament"
                ) { showCreateTournament = true }
                .cardStyle()
            } else {
                ForEach(app.library.tournaments.sorted { $0.tournament.createdAt > $1.tournament.createdAt }, id: \.tournament.id) { snapshot in
                    Button { app.present(.tournament(snapshot.tournament.id)) } label: {
                        TournamentRow(snapshot: snapshot)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var pastMatchesSection: some View {
        let records = app.library.matchHistory.sorted { $0.savedAt > $1.savedAt }
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Past matches")
                ForEach(records.prefix(10)) { record in
                    NavigationLink {
                        ScrollView { PastMatchCard(record: record).padding() }
                            .background(Theme.background)
                            .navigationTitle(record.snapshot.match.name)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        PastMatchRow(record: record)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

struct TournamentRow: View {
    let snapshot: TournamentSnapshot

    var body: some View {
        let leader = TournamentStandings.compute(snapshot).first
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.tournament.name).font(.headline)
                Text("\(snapshot.entrants.count) players · \(snapshot.tournament.rounds.count) round\(snapshot.tournament.rounds.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                statusPill
                if let leader, leader.holesPlayed > 0 {
                    Text("\(leader.entrant.name) \(leader.statusText)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .cardStyle(padding: 12)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch snapshot.tournament.status {
        case .registration: InfoPill(text: "Open", tint: Theme.water)
        case .inProgress: LiveBadge()
        case .finished: InfoPill(text: "Final", tint: .secondary)
        }
    }
}

struct PastMatchRow: View {
    @Environment(AppModel.self) private var app
    let record: MatchRecord

    var body: some View {
        let entries = Leaderboard.entries(for: record.snapshot)
        let mine = entries.first { $0.id == app.profile.id }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.snapshot.match.name).font(.headline).lineLimit(1)
                Text("\(record.snapshot.match.course.name) · \(record.savedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: -10) {
                ForEach(record.snapshot.participants.prefix(4)) { p in
                    AvatarView(avatar: p.avatar, size: 28, showsRing: true)
                }
            }
            if let mine {
                Text(mine.positionLabel)
                    .font(.headline)
                    .foregroundStyle(mine.position == 1 ? Theme.gold : .secondary)
                    .frame(minWidth: 30)
            }
        }
        .foregroundStyle(.primary)
        .cardStyle(padding: 12)
    }
}

struct OnlineStatusCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: app.isOnline ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                    .font(.headline)
                    .foregroundStyle(app.isOnline ? Theme.fairway : .secondary)
                    .frame(width: 36, height: 36)
                    .background((app.isOnline ? Theme.fairway : Color.secondary).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.isOnline ? "Online play is on" : "Offline demo mode").font(.subheadline.weight(.semibold))
                    Text(app.isOnline ? "Friends join with your code from their own phones." : "Friends are simulated. Connect a free Supabase project to play for real.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .cardStyle(padding: 12)
        }
        .buttonStyle(PressableStyle())
    }
}
