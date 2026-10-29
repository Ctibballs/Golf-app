import SwiftUI
import GolfKit

extension TrophyKind {
    var symbolName: String {
        switch self {
        case .champion, .runnerUp, .thirdPlace: return "trophy.fill"
        case .finisher: return "medal.fill"
        case .entered: return "rosette"
        }
    }

    var color: Color {
        switch self {
        case .champion: return Theme.gold
        case .runnerUp: return Theme.silver
        case .thirdPlace: return Theme.bronze
        case .finisher: return Theme.fairway
        case .entered: return Color.secondary
        }
    }
}

enum Ordinal {
    /// "1st", "2nd", "T3" (ties keep the golf-style label).
    static func text(_ position: Int?, label: String) -> String {
        guard let position else { return "–" }
        if label.hasPrefix("T") { return label }
        let suffix: String
        switch (position % 100, position % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(position)\(suffix)"
    }
}

/// A trophy, medal or ribbon for one cabinet entry.
struct TrophyFigure: View {
    let kind: TrophyKind
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: kind.isPodium ? size : size * 0.8))
            .foregroundStyle(kind.color.gradient)
            .frame(width: size * 1.2, height: size * 1.2)
            .accessibilityLabel(kind.displayName)
    }
}

/// Every tournament a player has entered: trophies on shelves, events in progress and
/// the full list of results.
struct TrophyCabinetView: View {
    @Environment(AppModel.self) private var app
    /// Whose cabinet to show; nil means yours.
    var playerID: UUID?
    var playerName: String?
    var avatar: Avatar?

    @State private var showCreate = false

    private var isMine: Bool { playerID == nil || playerID == app.profile.id }
    private var name: String { isMine ? app.profile.name : (playerName ?? "Player") }

    var body: some View {
        let cabinet = TrophyCabinet.build(for: playerID ?? app.profile.id, from: app.library.tournaments)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header(cabinet).reveal(0)
                if cabinet.isEmpty {
                    EmptyStateView(
                        title: isMine ? "Your cabinet is empty" : "No tournaments yet",
                        message: isMine
                            ? "Enter a tournament with a join code, or create your own. Every event you play earns its place here."
                            : "\(name) hasn't played a tournament with you yet.",
                        systemImage: "trophy",
                        actionTitle: isMine ? "Create a tournament" : nil
                    ) { showCreate = true }
                } else {
                    if !cabinet.finished.isEmpty {
                        shelves(cabinet.finished)
                    }
                    if !cabinet.inProgress.isEmpty {
                        inProgress(cabinet.inProgress)
                    }
                    history(cabinet.entries)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) { CreateTournamentView() }
    }

    private func header(_ cabinet: TrophyCabinet) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(isMine ? "Your record" : name)
                    Text("Trophy cabinet").font(.display(32))
                }
                Spacer()
                AvatarView(avatar: isMine ? app.profile.avatar : (avatar ?? app.profile.avatar), size: 48)
            }
            MetricGrid(items: [
                MetricItem(label: "Titles", value: "\(cabinet.titles)", tint: cabinet.titles > 0 ? Theme.gold : nil),
                MetricItem(label: "Podiums", value: "\(cabinet.podiums)"),
                MetricItem(label: "Events", value: "\(cabinet.eventsEntered)"),
                MetricItem(label: "Best", value: cabinet.bestFinish.map { Ordinal.text($0.position, label: $0.positionLabel) } ?? "—"),
            ], columns: 4, compact: true)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
        }
        .padding(.top, 8)
    }

    private func shelves(_ entries: [TrophyCabinetEntry]) -> some View {
        let rows = stride(from: 0, to: entries.count, by: 3).map { Array(entries[$0..<min($0 + 3, entries.count)]) }
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "The cabinet")
            VStack(spacing: 26) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    VStack(spacing: 0) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(0..<3, id: \.self) { column in
                                if column < row.count {
                                    TrophySlot(entry: row[column], order: rowIndex * 3 + column) { open(row[column]) }
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                }
                            }
                        }
                        // The shelf: a firm edge with a little depth below it.
                        Rectangle().fill(Color.primary.opacity(0.16)).frame(height: 1.5)
                        Rectangle().fill(Color.primary.opacity(0.04)).frame(height: 7)
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    private func inProgress(_ entries: [TrophyCabinetEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "In progress")
            DividedList(entries) { entry in
                Button { open(entry) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.body.weight(.medium))
                            Text(progressText(entry)).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        LiveBadge()
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func history(_ entries: [TrophyCabinetEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Every event", subtitle: "\(entries.count) tournament\(entries.count == 1 ? "" : "s")")
            DividedList(entries, inset: 46) { entry in
                Button { open(entry) } label: {
                    HStack(spacing: 12) {
                        Group {
                            if let trophy = entry.trophy {
                                TrophyFigure(kind: trophy, size: 20)
                            } else {
                                Image(systemName: "hourglass").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.body.weight(.medium)).lineLimit(1)
                            Text(detail(entry)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Ordinal.text(entry.position, label: entry.positionLabel))
                                .font(.figure(17, weight: .semibold))
                                .foregroundStyle(finishColor(entry))
                            Text(entry.resultText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func finishColor(_ entry: TrophyCabinetEntry) -> Color {
        guard let trophy = entry.trophy, trophy.isPodium else { return .primary }
        return trophy.color
    }

    private func progressText(_ entry: TrophyCabinetEntry) -> String {
        guard entry.position != nil else { return "Round 1 of \(entry.roundCount) · not started yet" }
        return "Round \(max(1, entry.roundsPlayed)) of \(entry.roundCount) · currently \(Ordinal.text(entry.position, label: entry.positionLabel)) · \(entry.resultText)"
    }

    private func detail(_ entry: TrophyCabinetEntry) -> String {
        var parts = [entry.date.formatted(date: .abbreviated, time: .omitted)]
        if let course = entry.courseNames.first { parts.append(entry.courseNames.count > 1 ? "\(course) +\(entry.courseNames.count - 1)" : course) }
        parts.append("\(entry.fieldSize) players")
        if entry.isFinished, let leader = entry.leaderName { parts.append("won by \(leader)") }
        return parts.joined(separator: " · ")
    }

    private func open(_ entry: TrophyCabinetEntry) {
        app.present(.tournament(entry.tournamentID))
    }
}

/// One trophy on a shelf: it rises into place, and titles give a little bounce.
private struct TrophySlot: View {
    let entry: TrophyCabinetEntry
    let order: Int
    let action: () -> Void
    @State private var shown = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let trophy = entry.trophy {
                    TrophyFigure(kind: trophy, size: trophy == .champion ? 44 : 38)
                        .symbolEffect(.bounce, value: shown && trophy == .champion)
                }
                Text(entry.name)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("\(Ordinal.text(entry.position, label: entry.positionLabel)) · \(entry.date.formatted(.dateTime.month(.abbreviated).year()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
            .offset(y: shown ? 0 : 14)
            .opacity(shown ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
        .onAppear {
            guard !shown else { return }
            withAnimation(.snappySpring.delay(0.1 + Double(order) * 0.08)) { shown = true }
        }
    }
}

/// The profile row: a peek at the shelf and the headline numbers.
struct TrophyCabinetRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let cabinet = TrophyCabinet.build(for: app.profile.id, from: app.library.tournaments)
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trophy cabinet")
                    Text(TrophyCabinetRow.summary(cabinet)).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "trophy")
            }
            Spacer()
            HStack(spacing: -6) {
                ForEach(cabinet.finished.filter { $0.trophy?.isPodium == true }.prefix(4)) { entry in
                    TrophyFigure(kind: entry.trophy ?? .finisher, size: 15)
                }
            }
        }
    }

    static func summary(_ cabinet: TrophyCabinet) -> String {
        guard !cabinet.isEmpty else { return "Enter a tournament to start your collection" }
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        return [plural(cabinet.titles, "title"), plural(cabinet.podiums, "podium"), plural(cabinet.eventsEntered, "event")].joined(separator: " · ")
    }
}
