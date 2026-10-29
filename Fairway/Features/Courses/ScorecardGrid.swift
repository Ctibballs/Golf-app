import SwiftUI
import GolfKit

struct ScorecardPlayerRow: Identifiable {
    let id: UUID
    let name: String
    var avatar: Avatar?
    var scores: [Int: Int]
}

/// A printed-scorecard style grid split into nines, with Out/In/Total columns.
struct ScorecardGrid: View {
    let course: Course
    let holes: [Int]
    var tee: TeeSet?
    var players: [ScorecardPlayerRow] = []
    var showsStrokeIndex = true
    var showsLengths = true
    var highlightedHole: Int?
    let units: UnitFormatter

    private let cellWidth: CGFloat = 34
    private let labelWidth: CGFloat = 70

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    segmentGrid(segment, totalLabel: segments.count == 1 ? "Tot" : (index == 0 ? "Out" : "In"), isLast: index == segments.count - 1)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var segments: [[Int]] {
        stride(from: 0, to: holes.count, by: 9).map { Array(holes[$0..<min($0 + 9, holes.count)]) }
    }

    private func segmentGrid(_ segment: [Int], totalLabel: String, isLast: Bool) -> some View {
        let showGrandTotal = isLast && segments.count > 1
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                label("Hole", bold: true)
                ForEach(segment, id: \.self) { n in
                    cell(Text("\(n)").font(.caption.weight(.heavy)), highlighted: n == highlightedHole)
                }
                cell(Text(totalLabel).font(.caption2.weight(.heavy)))
                if showGrandTotal { cell(Text("Tot").font(.caption2.weight(.heavy))) }
            }
            .background(Theme.fairway.opacity(0.14))

            GridRow {
                label("Par")
                ForEach(segment, id: \.self) { n in
                    cell(Text("\(course.hole(n)?.par ?? 0)").font(.caption.weight(.semibold)), highlighted: n == highlightedHole)
                }
                cell(Text("\(course.par(for: segment))").font(.caption.weight(.bold)))
                if showGrandTotal { cell(Text("\(course.par(for: holes))").font(.caption.weight(.bold))) }
            }

            if showsStrokeIndex && segment.contains(where: { course.hole($0)?.strokeIndex != nil }) {
                GridRow {
                    label("S.I.")
                    ForEach(segment, id: \.self) { n in
                        cell(Text(course.hole(n)?.strokeIndex.map { "\($0)" } ?? "–").font(.caption2).foregroundStyle(.secondary), highlighted: n == highlightedHole)
                    }
                    cell(Text(""))
                    if showGrandTotal { cell(Text("")) }
                }
            }

            if showsLengths && segment.contains(where: { course.hole($0)?.length(for: tee) != nil }) {
                GridRow {
                    label(units.system.distanceUnit == "m" ? "Metres" : "Yards")
                    ForEach(segment, id: \.self) { n in
                        cell(Text(course.hole(n)?.length(for: tee).map { units.distanceNumber($0) } ?? "–").font(.caption2).foregroundStyle(.secondary), highlighted: n == highlightedHole)
                    }
                    cell(Text(lengthTotal(segment)).font(.caption2.weight(.semibold)))
                    if showGrandTotal { cell(Text(lengthTotal(holes)).font(.caption2.weight(.semibold))) }
                }
            }

            ForEach(players) { player in
                GridRow {
                    HStack(spacing: 6) {
                        if let avatar = player.avatar { AvatarView(avatar: avatar, size: 20) }
                        Text(player.name).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .frame(width: labelWidth, height: 38, alignment: .leading)
                    ForEach(segment, id: \.self) { n in
                        ScoreBadge(strokes: player.scores[n], par: course.hole(n)?.par ?? 0, size: 26)
                            .frame(width: cellWidth, height: 38)
                            .background(n == highlightedHole ? Theme.fairway.opacity(0.1) : .clear)
                    }
                    cell(Text(total(player, segment)).font(.caption.weight(.heavy)))
                    if showGrandTotal { cell(Text(total(player, holes)).font(.caption.weight(.heavy))) }
                }
                .overlay(alignment: .top) { Divider() }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func label(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .font(bold ? .caption.weight(.heavy) : .caption.weight(.semibold))
            .foregroundStyle(bold ? .primary : .secondary)
            .frame(width: labelWidth, height: 30, alignment: .leading)
            .padding(.leading, 10)
    }

    private func cell(_ content: some View, highlighted: Bool = false) -> some View {
        content
            .frame(width: cellWidth, height: 30)
            .background(highlighted ? Theme.fairway.opacity(0.1) : .clear)
    }

    private func total(_ player: ScorecardPlayerRow, _ holes: [Int]) -> String {
        let values = holes.compactMap { player.scores[$0] }
        return values.isEmpty ? "–" : "\(values.reduce(0, +))"
    }

    private func lengthTotal(_ holes: [Int]) -> String {
        let lengths = holes.compactMap { course.hole($0)?.length(for: tee) }
        return lengths.isEmpty ? "" : units.distanceNumber(lengths.reduce(0, +))
    }
}

extension ScorecardPlayerRow {
    init(participant: Participant) {
        self.init(id: participant.id, name: participant.name, avatar: participant.avatar,
                  scores: Dictionary(participant.scores.map { ($0.holeNumber, $0.strokes) }, uniquingKeysWith: { $1 }))
    }

    init(round: Round, avatar: Avatar?) {
        self.init(id: round.playerID, name: round.playerName, avatar: avatar,
                  scores: Dictionary(round.scores.map { ($0.holeNumber, $0.strokes) }, uniquingKeysWith: { $1 }))
    }
}
