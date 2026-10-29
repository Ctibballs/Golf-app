import Foundation

public enum MatchServiceError: Error, LocalizedError, Equatable {
    case codeNotFound(String)
    case alreadyFinished
    case notFound
    case notConfigured
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .codeNotFound(let code): return "No game found with code \(JoinCode.spaced(code)). Check the letters and try again."
        case .alreadyFinished: return "That game has already finished."
        case .notFound: return "That game no longer exists."
        case .notConfigured: return "Online play isn't set up yet. Add your Supabase project in Settings → Online Play."
        case .server(let message): return message
        }
    }
}

/// Everything the app needs to host and join live matches and tournaments.
///
/// Implementations: `InMemoryMatchService` (offline demo with simulated friends) and
/// `SupabaseMatchService` (real online play through a free Supabase project).
public protocol MatchService: Sendable {
    /// False for the offline demo, so the UI can say friends are simulated.
    var isOnline: Bool { get }

    func createMatch(_ match: Match, host: Participant) async throws -> MatchSnapshot
    func joinMatch(code: String, as participant: Participant) async throws -> MatchSnapshot
    func snapshot(matchID: UUID) async throws -> MatchSnapshot
    /// Host only: status changes and settings.
    func updateMatch(_ match: Match) async throws
    /// Inserts or updates a participant this device scores for (yourself or a guest).
    func upsertParticipant(_ participant: Participant, matchID: UUID) async throws
    func removeParticipant(_ participantID: UUID, matchID: UUID) async throws

    func createTournament(_ tournament: Tournament, host: TournamentEntrant) async throws -> TournamentSnapshot
    func joinTournament(code: String, as entrant: TournamentEntrant) async throws -> TournamentSnapshot
    func tournamentSnapshot(id: UUID) async throws -> TournamentSnapshot
    /// Host only.
    func updateTournament(_ tournament: Tournament) async throws
}

/// Seeded random numbers so simulated players behave the same way every time a snapshot is built.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public init(_ uuid: UUID, salt: Int = 0) {
        var hash: UInt64 = 1469598103934665603
        withUnsafeBytes(of: uuid.uuid) { bytes in
            for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        }
        state = hash ^ UInt64(bitPattern: Int64(salt)) &* 0x9E3779B97F4A7C15
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Roughly normal sample (sum of uniforms).
    public mutating func gaussian(mean: Double, deviation: Double) -> Double {
        let sum = (0..<6).reduce(0.0) { acc, _ in acc + Double.random(in: 0...1, using: &self) }
        return mean + (sum - 3) * deviation / 0.707
    }
}
