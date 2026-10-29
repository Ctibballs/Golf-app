import SwiftUI
import GolfKit

/// A team's name in its colour, with an optional figure on the right.
struct TeamLabel: View {
    let team: Team
    var detail: String?

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Theme.teamColor(team.colorIndex))
                .frame(width: 3, height: 14)
            Eyebrow("\(team.name) team", color: Theme.teamColor(team.colorIndex))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Team members' avatars overlapping, edged in the team colour.
struct TeamAvatars: View {
    let team: Team
    let members: [Participant]
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(members.prefix(4)) { member in
                AvatarView(avatar: member.avatar, size: size)
            }
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Theme.teamColor(team.colorIndex))
                .frame(width: 3, height: size)
        }
        .frame(minWidth: size * 1.9, alignment: .leading)
    }
}

/// One team on a leaderboard.
struct TeamLeaderboardRow: View {
    let entry: TeamLeaderboardEntry
    var isMine = false

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.positionLabel)
                .font(.figure(15, weight: .semibold))
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(entry.position == 1 && entry.thru > 0 ? Theme.gold : .secondary)
            TeamAvatars(team: entry.team, members: entry.members, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMine ? "\(entry.team.name) (your team)" : entry.team.name)
                    .font(.body.weight(isMine ? .semibold : .medium))
                Text(entry.members.map(\.name).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.statusText)
                    .font(.figure(18, weight: .semibold))
                    .foregroundStyle(entry.statusText.hasPrefix("-") ? Theme.flag : .primary)
                    .contentTransition(.numericText())
                Text(progress)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var progress: String {
        if entry.isFinished { return "Finished" }
        if entry.thru == 0 { return entry.currentHole.map { "On hole \($0)" } ?? "Not started" }
        return "Thru \(entry.thru)"
    }
}
