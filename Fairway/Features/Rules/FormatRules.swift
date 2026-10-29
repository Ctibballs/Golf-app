import SwiftUI
import GolfKit

/// How to play each format, in plain words: the steps, the scoring, the handicap
/// allowances and how to set it up in Fairway.
struct FormatRules: Identifiable, Hashable {
    enum Kind: String {
        case individual = "Individual"
        case team = "Team"
    }

    let id: String
    let name: String
    var alsoKnownAs: String?
    let kind: Kind
    let players: String
    let symbolName: String
    let tagline: String
    let howToPlay: [String]
    let scoring: [String]
    let handicaps: [String]
    let goodToKnow: [String]
    let inFairway: String

    static let individual: [FormatRules] = [strokePlay, matchPlay, stableford, skins]
    static let team: [FormatRules] = [fourBall, bestBall, scramble, alternateShot, chapman]
    static let all = individual + team

    static func rules(for format: ScoringFormat) -> FormatRules {
        switch format {
        case .strokePlay: return strokePlay
        case .matchPlay: return matchPlay
        case .stableford: return stableford
        case .skins: return skins
        }
    }

    static func rules(for format: TeamFormat) -> FormatRules {
        switch format {
        case .fourBall: return fourBall
        case .bestBall, .bestTwo, .aggregate: return bestBall
        case .scramble: return scramble
        case .alternateShot: return alternateShot
        case .chapman: return chapman
        }
    }

    /// The rules that matter most for a match: its team format if it has one.
    static func rules(for match: Match) -> FormatRules {
        if match.isTeamGame, let team = match.teamFormat { return rules(for: team) }
        return rules(for: match.format)
    }

    static let disclaimer = "These are simplified summaries for friendly games. Competitions are played under the Rules of Golf (The R&A and USGA) and the World Handicap System, and a club's terms of competition always come first."

    // MARK: - Individual

    static let strokePlay = FormatRules(
        id: "strokePlay", name: "Stroke play", alsoKnownAs: "Medal", kind: .individual, players: "Any number",
        symbolName: "list.number", tagline: "Every shot counts. Lowest total wins.",
        howToPlay: [
            "Everyone plays their own ball from the tee into the hole, on every hole.",
            "Count every stroke, including penalty strokes.",
            "Hole out on every hole before moving on to the next tee.",
        ],
        scoring: [
            "Add up all your strokes for the round. The lowest total wins.",
            "Scores are usually shown against par: −2 is two under, E is level par, +5 is five over.",
            "Ties are often settled on countback: the best score over the last 9, 6, 3 and then 1 holes.",
        ],
        handicaps: [
            "Net score is your gross score minus your course handicap. Strokes are given on the hardest holes first, by stroke index.",
            "The World Handicap System recommends 95% of course handicap for individual stroke play competitions. Fairway uses the full course handicap for casual games.",
        ],
        goodToKnow: [
            "Every hole needs a score, so you can't walk off after a bad one.",
            "For handicap purposes a blow-up hole is capped at net double bogey anyway, so in a casual game many players pick up there.",
        ],
        inFairway: "Choose Stroke Play when you set up a round or match, and switch on handicaps for net scores."
    )

    static let matchPlay = FormatRules(
        id: "matchPlay", name: "Match play", kind: .individual, players: "Two players, or two teams",
        symbolName: "person.2", tagline: "Win holes, not strokes.",
        howToPlay: [
            "Play each hole against your opponent. The lower score wins the hole.",
            "If you take the same number of strokes, the hole is halved.",
            "You can concede a putt, a hole or the whole match at any time. A concession can't be refused or taken back.",
        ],
        scoring: [
            "The match is counted in holes: 2 UP means you've won two more holes than your opponent, and AS (all square) means level.",
            "The match ends as soon as one side is ahead by more holes than are left, written like 3&2: three up with two to play.",
            "If it's level after the last hole, the match is halved, or you play extra holes to settle it.",
        ],
        handicaps: [
            "The lower handicap plays off scratch, and the other player receives the full difference between the two course handicaps.",
            "Those strokes are taken on the hardest holes, by stroke index.",
        ],
        goodToKnow: [
            "Only holes count, so a disaster costs you just one hole.",
            "With more than two players, Fairway ranks everyone by holes won outright.",
        ],
        inFairway: "Choose Match Play. For two against two, switch on Play in teams and pick Four-ball, Foursomes, Chapman or another team format."
    )

    static let stableford = FormatRules(
        id: "stableford", name: "Stableford", kind: .individual, players: "Any number",
        symbolName: "star.circle", tagline: "Points for every hole. Most points wins.",
        howToPlay: [
            "Play your own ball and count your strokes as normal.",
            "Your score on each hole earns points against par, or against net par when you play off handicaps.",
            "Once you can't score a point on a hole, pick up and move on.",
        ],
        scoring: [
            "Net double bogey or worse: 0 points",
            "Bogey: 1 point",
            "Par: 2 points",
            "Birdie: 3 points",
            "Eagle: 4 points",
            "Albatross: 5 points",
            "Most points wins. 36 points over 18 holes means you played to your handicap.",
        ],
        handicaps: [
            "Handicap strokes come off on the hardest holes first, so a gross bogey on a stroke hole is a net par worth 2 points.",
            "The World Handicap System recommends 95% of course handicap for individual Stableford competitions.",
        ],
        goodToKnow: [
            "A bad hole costs only that hole's points, which keeps rounds quick and friendly.",
        ],
        inFairway: "Choose Stableford. Fairway turns your strokes into points as you score."
    )

    static let skins = FormatRules(
        id: "skins", name: "Skins", kind: .individual, players: "Best with three or four",
        symbolName: "dollarsign.circle", tagline: "Every hole is a prize. Win it outright to take it.",
        howToPlay: [
            "Each hole is worth one skin, often with a small stake.",
            "The player with the lowest score on the hole wins the skin, but only if nobody ties them.",
            "If the lowest score is tied, nobody wins and the skin carries over to the next hole.",
        ],
        scoring: [
            "Carry-overs build up: win the hole after three ties and you take four skins.",
            "Most skins wins. Skins still carried after the last hole go to a playoff, or are simply left on the table.",
        ],
        handicaps: [
            "Net skins give strokes by stroke index, as in stroke play. Some groups use a reduced allowance so the low handicaps aren't shut out.",
        ],
        goodToKnow: [
            "Some groups play validation: to keep a skin, its winner must at least tie the next hole.",
        ],
        inFairway: "Choose Skins. Fairway keeps track of carry-overs and who has won what. Skins is played as individuals."
    )

    // MARK: - Team

    static let fourBall = FormatRules(
        id: "fourBall", name: "Four-ball", alsoKnownAs: "Better ball", kind: .team, players: "Pairs",
        symbolName: "person.2", tagline: "Two against two. The better ball counts.",
        howToPlay: [
            "Everyone plays their own ball for the whole hole.",
            "On each hole, the better of the two partners' scores is the team's score.",
            "Play it as stroke play, for a team total, or as match play, side against side.",
        ],
        scoring: [
            "Stroke play: add up the team's better-ball scores. Lowest total wins.",
            "Match play: compare the two sides' better balls on each hole.",
            "Stableford: the better points score on each hole counts.",
        ],
        handicaps: [
            "Stroke play and Stableford: each player gets 85% of their course handicap.",
            "Match play: 90%, then the lowest player plays off scratch and the others receive the difference.",
        ],
        goodToKnow: [
            "If one partner is safely on the green, the other can attack the pin.",
            "A player can pick up once their score can't help the team.",
        ],
        inFairway: "Switch on Play in teams and choose Four-ball. The host puts players into pairs in the lobby, or lets Fairway balance them."
    )

    static let bestBall = FormatRules(
        id: "bestBall", name: "Best ball", kind: .team, players: "Teams of three or four",
        symbolName: "person.3", tagline: "Everyone plays their own ball. The lowest score counts.",
        howToPlay: [
            "Each player plays their own ball for the whole hole.",
            "The lowest score in the team on each hole is the team's score.",
            "Popular variations count the best two scores on each hole, or every score (aggregate).",
        ],
        scoring: [
            "Add up the team's counting scores for the total, or use Stableford points.",
            "Lowest total, or most points, wins.",
        ],
        handicaps: [
            "The World Handicap System recommends 75% of course handicap when one score of four counts, 85% when two count, and 100% when three or four count.",
        ],
        goodToKnow: [
            "With several players on every shot, a team can afford a riskier line.",
        ],
        inFairway: "Choose Best ball for one score per hole, Best two to count two, or Aggregate to count everyone."
    )

    static let scramble = FormatRules(
        id: "scramble", name: "Scramble", kind: .team, players: "Teams of two to four",
        symbolName: "arrow.triangle.merge", tagline: "Everyone hits. Play the best shot.",
        howToPlay: [
            "Everyone tees off.",
            "The team picks the best drive, and every player plays their next shot from that spot: within a club length, no nearer the hole.",
            "Keep choosing the best shot and playing from there until the ball is holed.",
        ],
        scoring: [
            "The team records one score on each hole.",
            "Lowest team total wins. Scramble scores are low, so expect plenty of birdies.",
        ],
        handicaps: [
            "Four players: 25%, 20%, 15% and 10% of course handicaps, lowest handicap first.",
            "Three players: 30%, 20% and 10%.",
            "Two players: 35% of the lower course handicap and 15% of the higher.",
        ],
        goodToKnow: [
            "In a Texas scramble each player's drive has to be used a minimum number of times.",
            "Scramble scores don't count toward a handicap index.",
        ],
        inFairway: "Choose Scramble. Any player in the team can enter the team's score, and the most recent entry counts."
    )

    static let alternateShot = FormatRules(
        id: "alternateShot", name: "Foursomes", alsoKnownAs: "Alternate shot", kind: .team, players: "Pairs",
        symbolName: "arrow.left.arrow.right", tagline: "Two players, one ball, taking turns.",
        howToPlay: [
            "Partners share one ball and take turns hitting it until it's holed.",
            "Tee shots alternate too: one partner drives on the odd-numbered holes, the other on the even.",
            "Penalty strokes don't change whose turn it is.",
        ],
        scoring: [
            "The team records one score on each hole.",
            "Play it as stroke play, for a team total, or as match play.",
        ],
        handicaps: [
            "Stroke play: 50% of the partners' combined course handicaps.",
            "Match play: 50% of the difference between the two sides' combined course handicaps.",
        ],
        goodToKnow: [
            "It's the format of the foursomes sessions at the Ryder Cup: a real test of partnership.",
        ],
        inFairway: "Choose Foursomes. Either partner can enter the team's score."
    )

    static let chapman = FormatRules(
        id: "chapman", name: "Chapman", alsoKnownAs: "Pinehurst", kind: .team, players: "Pairs",
        symbolName: "arrow.triangle.swap", tagline: "Both drive, swap, choose one, then alternate.",
        howToPlay: [
            "Both partners tee off.",
            "Swap balls: each plays their second shot with their partner's ball.",
            "Choose the better of the two balls after the second shots.",
            "From there, alternate shots with that ball until it's holed. The player who didn't hit the chosen second shot plays next.",
        ],
        scoring: [
            "The team records one score on each hole, in stroke play or match play.",
        ],
        handicaps: [
            "60% of the lower course handicap plus 40% of the higher.",
        ],
        goodToKnow: [
            "It's named after Dick Chapman, the American amateur who made it popular.",
        ],
        inFairway: "Choose Chapman. Either partner can enter the team's score."
    )
}

// MARK: - Views

/// Every format, grouped into individual and team games.
struct RulesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("How to play")
                    Text("Formats and rules").font(.display(32))
                    Text("The ways to play a round, from a straight medal to a Chapman, with the scoring and handicap allowances for each.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .reveal(0)
                section("Individual", FormatRules.individual).reveal(1)
                section("Teams", FormatRules.team).reveal(2)
                Text(FormatRules.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ rules: [FormatRules]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: title)
            DividedList(rules, inset: 38) { rule in
                NavigationLink {
                    RuleDetailView(rule: rule)
                } label: {
                    NavigationRowLabel(title: rule.name, subtitle: rule.tagline, systemImage: rule.symbolName)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

/// One format in full.
struct RuleDetailView: View {
    let rule: FormatRules

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("\(rule.kind.rawValue) · \(rule.players)")
                    Text(rule.name).font(.display(34))
                    if let aka = rule.alsoKnownAs {
                        Text("Also known as \(aka)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(rule.tagline).font(.title3).padding(.top, 4)
                }
                .padding(.top, 8)
                .reveal(0)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "How to play")
                    ForEach(Array(rule.howToPlay.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.figure(15, weight: .semibold))
                                .foregroundStyle(Theme.fairway)
                                .frame(width: 18, alignment: .leading)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .reveal(1)

                bullets("Scoring", rule.scoring)
                bullets("Handicaps", rule.handicaps)
                bullets("Good to know", rule.goodToKnow)

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("In Fairway", color: Theme.fairway)
                    Text(rule.inFairway).font(.subheadline)
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.fairway).frame(width: 2)
                }

                Text(FormatRules.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullets(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A format's rules in a sheet, from setup screens and the lobby.
struct RuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rule: FormatRules

    var body: some View {
        NavigationStack {
            RuleDetailView(rule: rule)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationDragIndicator(.visible)
    }
}
