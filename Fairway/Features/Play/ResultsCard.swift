import SwiftUI
import GolfKit

/// What a results card shows: everyone's ranking, a podium and the hole-by-hole card.
struct ResultsCardModel: Equatable {
    var title: String
    var courseName: String
    var date: Date
    var format: ScoringFormat?
    var isNet: Bool
    var isFinished: Bool
    var course: Course
    var holes: [Int]
    var tee: TeeSet?
    /// Rankings, best first. Empty for a solo round.
    var entries: [LeaderboardEntry]
    /// Scorecard rows in ranking order.
    var rows: [ScorecardPlayerRow]

    init(snapshot: MatchSnapshot) {
        let match = snapshot.match
        let entries = Leaderboard.entries(for: snapshot)
        self.title = match.name
        self.courseName = match.course.name
        self.date = match.finishedAt ?? match.startedAt ?? match.createdAt
        self.format = match.format
        self.isNet = match.useHandicaps
        self.isFinished = match.status == .finished
        self.course = match.course
        self.holes = match.holeNumbers
        self.tee = match.tee
        self.entries = entries
        self.rows = entries.map { ScorecardPlayerRow(participant: $0.participant) }
    }

    init(round: Round, avatar: Avatar?) {
        self.title = round.course.name
        self.courseName = round.course.name
        self.date = round.date
        self.format = nil
        self.isNet = false
        self.isFinished = round.isComplete
        self.course = round.course
        self.holes = round.holeNumbers
        self.tee = round.tee
        self.entries = []
        self.rows = [ScorecardPlayerRow(round: round, avatar: avatar)]
    }

    private var played: [LeaderboardEntry] { entries.filter { $0.thru > 0 } }

    /// A podium for the top three once there are at least four players.
    var showsPodium: Bool { played.count >= 4 }

    var headline: String {
        if let leader = played.first {
            let tied = played.filter { $0.position == leader.position }
            if tied.count > 1 {
                return "\(ListFormatter.localizedString(byJoining: tied.map(\.participant.name))) \(isFinished ? "tie" : "are tied") on \(leader.statusText)"
            }
            return "\(leader.participant.name) \(isFinished ? "wins" : "leads") with \(leader.statusText)"
        }
        guard entries.isEmpty, let row = rows.first, !row.scores.isEmpty else { return "" }
        let strokes = row.scores.values.reduce(0, +)
        let par = row.scores.keys.compactMap { course.hole($0)?.par }.reduce(0, +)
        return "\(row.name) shot \(strokes) (\(Leaderboard.formatToPar(strokes - par)))"
    }

    var shareText: String {
        let place = title == courseName ? courseName : "\(title) at \(courseName)"
        return "\(place): \(headline). Scored with Fairway."
    }
}

/// Rankings, a podium for the top three and everyone's scorecard. The same view is drawn
/// on screen and into the image people share.
struct ResultsCard: View {
    let model: ResultsCardModel
    let units: UnitFormatter
    /// Off when drawing an image: everything appears in its final state and nothing scrolls.
    var interactive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if model.showsPodium {
                Podium(entries: Array(model.entries.prefix(3)), animated: interactive)
            }
            if !model.entries.isEmpty {
                rankings
            }
            ScorecardGrid(
                course: model.course, holes: model.holes, tee: model.tee, players: model.rows,
                showsStrokeIndex: false, showsLengths: false, units: units, scrolls: interactive
            )
            if !interactive {
                HStack(spacing: 8) {
                    FlagMark(animated: false).frame(width: 14, height: 17)
                    Text("Scored with Fairway").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(eyebrowText)
            Text(model.title).font(.display(26)).lineLimit(2)
            if model.title != model.courseName {
                Text(model.courseName).font(.subheadline).foregroundStyle(.secondary)
            }
            if !model.headline.isEmpty {
                Text(model.headline).font(.subheadline.weight(.medium)).padding(.top, 2)
            }
        }
    }

    private var eyebrowText: String {
        var parts = [model.format?.displayName ?? "Round"]
        if model.isNet { parts.append("Net") }
        parts.append(model.date.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    /// Red for scores under par, as on a printed leaderboard.
    private func isUnderPar(_ entry: LeaderboardEntry) -> Bool {
        guard model.format == .strokePlay, entry.thru > 0 else { return false }
        return (model.isNet ? entry.netToPar ?? entry.grossToPar : entry.grossToPar) < 0
    }

    private var rankings: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("POS").frame(width: 38, alignment: .leading)
                Text("PLAYER")
                Spacer()
                Text("GROSS").frame(width: 56, alignment: .trailing)
                Text("SCORE").frame(width: 66, alignment: .trailing)
            }
            .font(.eyebrow)
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            Hairline()
            ForEach(model.entries) { entry in
                HStack(spacing: 0) {
                    Text(entry.thru > 0 ? entry.positionLabel : "–")
                        .font(.figure(15, weight: .semibold))
                        .foregroundStyle(entry.position == 1 && entry.thru > 0 ? Theme.gold : .primary)
                        .frame(width: 38, alignment: .leading)
                    AvatarView(avatar: entry.participant.avatar, size: 26)
                        .padding(.trailing, 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.participant.name).font(.body.weight(.medium)).lineLimit(1)
                        if !entry.isFinished && entry.thru > 0 && entry.thru < model.holes.count {
                            Text("Thru \(entry.thru)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(entry.thru > 0 ? "\(entry.gross)" : "–")
                        .font(.figure(15))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                    Text(entry.statusText)
                        .font(.figure(17, weight: .semibold))
                        .foregroundStyle(isUnderPar(entry) ? Theme.flag : .primary)
                        .frame(width: 66, alignment: .trailing)
                }
                .padding(.vertical, 10)
                Hairline()
            }
        }
    }
}

/// First, second and third on steps of different heights, rising into place.
struct Podium: View {
    let entries: [LeaderboardEntry]
    var animated = true
    @State private var raised = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if entries.count > 1 { step(entries[1], height: 64, metal: Theme.silver, order: 1) }
            if let first = entries.first { step(first, height: 92, metal: Theme.gold, order: 2, isWinner: true) }
            if entries.count > 2 { step(entries[2], height: 44, metal: Theme.bronze, order: 0) }
        }
        .padding(.top, 18)
        .onAppear {
            guard animated, !raised else { return }
            raised = true
        }
    }

    private func step(_ entry: LeaderboardEntry, height: CGFloat, metal: Color, order: Int, isWinner: Bool = false) -> some View {
        let shown = raised || !animated
        return VStack(spacing: 6) {
            AvatarView(avatar: entry.participant.avatar, size: isWinner ? 54 : 44)
                .overlay(alignment: .top) {
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.gold)
                            .offset(y: -15)
                            .symbolEffect(.bounce, value: shown)
                    }
                }
            Text(entry.participant.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(entry.statusText)
                .font(.figure(14))
                .foregroundStyle(.secondary)
            ZStack(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.05))
                Rectangle().fill(metal).frame(height: 3)
                Text(entry.positionLabel)
                    .font(.display(isWinner ? 32 : 26, weight: .regular))
                    .foregroundStyle(metal)
                    .padding(.top, 10)
            }
            .frame(height: height)
            .scaleEffect(y: shown ? 1 : 0.02, anchor: .bottom)
        }
        .frame(maxWidth: .infinity)
        .opacity(shown ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.15 + Double(order) * 0.18), value: shown)
    }
}

/// Renders a results card to an image and offers it through the share sheet.
struct ShareScorecardButton: View {
    let model: ResultsCardModel
    let units: UnitFormatter
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: image,
                    subject: Text(model.title),
                    message: Text(model.shareText),
                    preview: SharePreview(model.title, image: image)
                ) {
                    Label("Share scorecard", systemImage: "square.and.arrow.up")
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing scorecard…")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
        .task(id: model) { await render() }
    }

    @MainActor
    private func render() async {
        let card = ResultsCard(model: model, units: units, interactive: false)
            .padding(28)
            .frame(width: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        image = renderer.uiImage.map { Image(uiImage: $0) }
    }
}
