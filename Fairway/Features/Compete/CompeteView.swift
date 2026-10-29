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
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { showCreateMatch = true } label: {
                            HStack {
                                Image(systemName: "person.2")
                                Text("Host a match")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .padding(.horizontal, 18)
                        }
                        .buttonStyle(PrimaryButtonStyle(height: 56))

                        Button { showJoin = true } label: {
                            HStack {
                                Image(systemName: "number")
                                Text("Join with a code")
                                Spacer()
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 18)
                        }
                        .buttonStyle(SecondaryButtonStyle(height: 56))

                        OnlineStatusRow()
                            .padding(.top, 6)
                    }
                    .reveal(0)
                    if !app.library.activeGames.isEmpty {
                        ActiveGamesSection()
                    }
                    tournamentsSection.reveal(1)
                    pastMatchesSection
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "How to play")
                        NavigationLink {
                            RulesView()
                        } label: {
                            NavigationRowLabel(title: "Formats and rules", subtitle: "Stroke play, match play, Stableford, skins, four-ball, scramble, foursomes and more", systemImage: "book")
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            .navigationTitle("Compete")
            .sheet(isPresented: $showJoin) { JoinGameView() }
            .sheet(isPresented: $showCreateMatch) { CreateMatchView() }
            .sheet(isPresented: $showCreateTournament) { CreateTournamentView() }
        }
    }

    @ViewBuilder
    private var tournamentsSection: some View {
        let tournaments = app.library.tournaments.sorted { $0.tournament.createdAt > $1.tournament.createdAt }
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Tournaments", actionTitle: "New") { showCreateTournament = true }
            if tournaments.isEmpty {
                EmptyStateView(
                    title: "Run your own major",
                    message: "Multi-round events with a live leaderboard, every player's current hole and detailed stats.",
                    systemImage: "trophy",
                    actionTitle: "Create tournament"
                ) { showCreateTournament = true }
            } else {
                DividedList(tournaments, inset: 38) { snapshot in
                    Button { app.present(.tournament(snapshot.tournament.id)) } label: {
                        TournamentRow(snapshot: snapshot)
                    }
                    .buttonStyle(PressableStyle())
                }
                Hairline()
                NavigationLink {
                    TrophyCabinetView()
                } label: {
                    NavigationRowLabel(
                        title: "Your trophy cabinet",
                        subtitle: TrophyCabinetRow.summary(TrophyCabinet.build(for: app.profile.id, from: app.library.tournaments)),
                        systemImage: "trophy"
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder
    private var pastMatchesSection: some View {
        let records = Array(app.library.matchHistory.sorted { $0.savedAt > $1.savedAt }.prefix(10))
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Past matches")
                DividedList(records) { record in
                    NavigationLink {
                        ScrollView {
                            PastMatchSection(record: record)
                                .padding(.horizontal, Theme.gutter)
                        }
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
            Image(systemName: "trophy")
                .font(.body)
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.tournament.name).font(.body.weight(.medium)).lineLimit(1)
                Text(detail(leader)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            status
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func detail(_ leader: TournamentStanding?) -> String {
        var parts = ["\(snapshot.entrants.count) players", "\(snapshot.tournament.rounds.count) round\(snapshot.tournament.rounds.count == 1 ? "" : "s")"]
        if let leader, leader.holesPlayed > 0 { parts.append("\(leader.entrant.name) leads \(leader.statusText)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var status: some View {
        switch snapshot.tournament.status {
        case .registration: Eyebrow("Open", color: Theme.water)
        case .inProgress: LiveBadge()
        case .finished: Eyebrow("Final")
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
                Text(record.snapshot.match.name).font(.body.weight(.medium)).lineLimit(1)
                Text("\(record.snapshot.match.course.name) · \(record.savedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: -8) {
                ForEach(record.snapshot.participants.prefix(4)) { p in
                    AvatarView(avatar: p.avatar, size: 24)
                }
            }
            if let mine {
                Text(mine.positionLabel)
                    .font(.figure(17, weight: .semibold))
                    .foregroundStyle(mine.position == 1 ? Theme.gold : .secondary)
                    .frame(minWidth: 30, alignment: .trailing)
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

struct OnlineStatusRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(app.isOnline ? Theme.fairway : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(app.isOnline ? "Online play is on. Friends join from their own phones." : "Offline demo mode: friends are simulated.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text(app.isOnline ? "Settings" : "Set up")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.fairway)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}
