import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SupabaseConfig: Codable, Hashable, Sendable {
    /// e.g. https://abcdefgh.supabase.co
    public var url: URL
    /// The project's public "anon" key. Row-level security protects the data.
    public var anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Accepts "abcdefgh", "abcdefgh.supabase.co" or a full URL.
    public init?(project: String, anonKey: String) {
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !key.isEmpty else { return nil }
        let urlString: String
        if trimmed.hasPrefix("http") {
            urlString = trimmed
        } else if trimmed.contains(".") {
            urlString = "https://\(trimmed)"
        } else {
            urlString = "https://\(trimmed).supabase.co"
        }
        guard let url = URL(string: urlString.hasSuffix("/") ? String(urlString.dropLast()) : urlString) else { return nil }
        self.init(url: url, anonKey: key)
    }
}

public struct SupabaseSession: Codable, Hashable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: String
}

/// Online matches through a free Supabase project, using plain REST (PostgREST + GoTrue).
///
/// Each device signs in anonymously. Hosts own their match row; every participant row is
/// owned by the device that scores it, so row-level security stops anyone editing someone
/// else's card. Clients poll for changes. See `supabase/schema.sql` in the repo.
public actor SupabaseMatchService: MatchService {
    public nonisolated let isOnline = true

    let config: SupabaseConfig
    let transport: HTTPTransport
    private var session: SupabaseSession?
    private let onSessionChange: @Sendable (SupabaseSession?) -> Void
    private let now: @Sendable () -> Date

    public init(
        config: SupabaseConfig,
        session: SupabaseSession? = nil,
        transport: HTTPTransport = URLSessionTransport(),
        onSessionChange: @escaping @Sendable (SupabaseSession?) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.session = session
        self.transport = transport
        self.onSessionChange = onSessionChange
        self.now = now
    }

    // MARK: - Rows

    struct MatchRow: Codable {
        var id: UUID
        var code: String
        var status: String
        var tournament_id: UUID?
        var payload: Match
    }

    struct ParticipantRow: Codable {
        var match_id: UUID
        var participant_id: UUID
        var payload: Participant
    }

    struct TournamentRow: Codable {
        var id: UUID
        var code: String
        var status: String
        var payload: Tournament
    }

    struct EntrantRow: Codable {
        var tournament_id: UUID
        var entrant_id: UUID
        var payload: TournamentEntrant
    }

    struct Payload<T: Decodable>: Decodable {
        var payload: T
    }

    // MARK: - Matches

    public func createMatch(_ match: Match, host: Participant) async throws -> MatchSnapshot {
        var match = match
        for attempt in 0..<6 {
            do {
                try await rest("POST", "matches", body: MatchRow(id: match.id, code: match.code, status: match.status.rawValue, tournament_id: match.tournamentID, payload: match))
                break
            } catch HTTPError.status(409, _) where attempt < 5 {
                // Code already used by an active game: pick another.
                match.code = JoinCode.generate()
            }
        }
        try await upsertParticipant(host, matchID: match.id)
        return try await snapshot(matchID: match.id)
    }

    public func joinMatch(code: String, as participant: Participant) async throws -> MatchSnapshot {
        let normalized = JoinCode.normalize(code)
        let rows: [Payload<Match>] = try await fetch("matches", query: [
            ("code", "eq.\(normalized)"), ("select", "payload"), ("order", "created_at.desc"), ("limit", "1"),
        ])
        guard let match = rows.first?.payload else { throw MatchServiceError.codeNotFound(normalized) }
        guard match.status != .finished else { throw MatchServiceError.alreadyFinished }
        try await upsertParticipant(participant, matchID: match.id)
        return try await snapshot(matchID: match.id)
    }

    public func snapshot(matchID: UUID) async throws -> MatchSnapshot {
        async let matchRows: [Payload<Match>] = fetch("matches", query: [("id", "eq.\(matchID.uuidString)"), ("select", "payload")])
        async let participantRows: [Payload<Participant>] = fetch("participants", query: [
            ("match_id", "eq.\(matchID.uuidString)"), ("select", "payload"), ("order", "created_at.asc"),
        ])
        guard let match = try await matchRows.first?.payload else { throw MatchServiceError.notFound }
        return MatchSnapshot(match: match, participants: try await participantRows.map(\.payload))
    }

    public func updateMatch(_ match: Match) async throws {
        struct Patch: Encodable { var status: String; var payload: Match }
        try await rest("PATCH", "matches", query: [("id", "eq.\(match.id.uuidString)")], body: Patch(status: match.status.rawValue, payload: match))
    }

    public func upsertParticipant(_ participant: Participant, matchID: UUID) async throws {
        try await rest(
            "POST", "participants",
            query: [("on_conflict", "match_id,participant_id")],
            body: ParticipantRow(match_id: matchID, participant_id: participant.id, payload: participant),
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    public func removeParticipant(_ participantID: UUID, matchID: UUID) async throws {
        try await rest("DELETE", "participants", query: [
            ("match_id", "eq.\(matchID.uuidString)"), ("participant_id", "eq.\(participantID.uuidString)"),
        ], body: Optional<String>.none)
    }

    // MARK: - Tournaments

    public func createTournament(_ tournament: Tournament, host: TournamentEntrant) async throws -> TournamentSnapshot {
        var tournament = tournament
        for attempt in 0..<6 {
            do {
                try await rest("POST", "tournaments", body: TournamentRow(id: tournament.id, code: tournament.code, status: tournament.status.rawValue, payload: tournament))
                break
            } catch HTTPError.status(409, _) where attempt < 5 {
                tournament.code = JoinCode.generate()
            }
        }
        try await upsertEntrant(host, tournamentID: tournament.id)
        return try await tournamentSnapshot(id: tournament.id)
    }

    public func joinTournament(code: String, as entrant: TournamentEntrant) async throws -> TournamentSnapshot {
        let normalized = JoinCode.normalize(code)
        let rows: [Payload<Tournament>] = try await fetch("tournaments", query: [
            ("code", "eq.\(normalized)"), ("status", "neq.finished"), ("select", "payload"), ("limit", "1"),
        ])
        guard let tournament = rows.first?.payload else { throw MatchServiceError.codeNotFound(normalized) }
        try await upsertEntrant(entrant, tournamentID: tournament.id)
        return try await tournamentSnapshot(id: tournament.id)
    }

    public func tournamentSnapshot(id: UUID) async throws -> TournamentSnapshot {
        let rows: [Payload<Tournament>] = try await fetch("tournaments", query: [("id", "eq.\(id.uuidString)"), ("select", "payload")])
        guard let tournament = rows.first?.payload else { throw MatchServiceError.notFound }
        let entrants: [Payload<TournamentEntrant>] = try await fetch("tournament_entrants", query: [
            ("tournament_id", "eq.\(id.uuidString)"), ("select", "payload"), ("order", "created_at.asc"),
        ])

        var rounds: [Int: MatchSnapshot] = [:]
        let matchIDs = tournament.rounds.compactMap(\.matchID)
        if !matchIDs.isEmpty {
            let list = "in.(\(matchIDs.map(\.uuidString).joined(separator: ",")))"
            async let matchRows: [Payload<Match>] = fetch("matches", query: [("id", list), ("select", "payload")])
            async let participantRows: [ParticipantRow] = fetch("participants", query: [("match_id", list), ("select", "match_id,participant_id,payload")])
            let matches = try await matchRows.map(\.payload)
            let participants = try await participantRows
            for round in tournament.rounds {
                guard let matchID = round.matchID, let match = matches.first(where: { $0.id == matchID }) else { continue }
                rounds[round.number] = MatchSnapshot(match: match, participants: participants.filter { $0.match_id == matchID }.map(\.payload))
            }
        }
        return TournamentSnapshot(tournament: tournament, entrants: entrants.map(\.payload), rounds: rounds)
    }

    public func updateTournament(_ tournament: Tournament) async throws {
        struct Patch: Encodable { var status: String; var payload: Tournament }
        try await rest("PATCH", "tournaments", query: [("id", "eq.\(tournament.id.uuidString)")], body: Patch(status: tournament.status.rawValue, payload: tournament))
    }

    func upsertEntrant(_ entrant: TournamentEntrant, tournamentID: UUID) async throws {
        try await rest(
            "POST", "tournament_entrants",
            query: [("on_conflict", "tournament_id,entrant_id")],
            body: EntrantRow(tournament_id: tournamentID, entrant_id: entrant.id, payload: entrant),
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    // MARK: - Auth

    /// Signs in anonymously the first time, then refreshes the token as it nears expiry.
    func accessToken() async throws -> String {
        if let session, session.expiresAt.timeIntervalSince(now()) > 60 {
            return session.accessToken
        }
        if let refresh = session?.refreshToken, let refreshed = try? await authenticate(path: "token", query: [("grant_type", "refresh_token")], body: ["refresh_token": refresh]) {
            setSession(refreshed)
            return refreshed.accessToken
        }
        let fresh = try await authenticate(path: "signup", query: [], body: [String: String]())
        setSession(fresh)
        return fresh.accessToken
    }

    private func setSession(_ value: SupabaseSession?) {
        session = value
        onSessionChange(value)
    }

    struct AuthResponse: Decodable {
        var access_token: String
        var refresh_token: String
        var expires_in: Double?
        var expires_at: Double?
        var user: User?
        struct User: Decodable { var id: String }
    }

    func authenticate(path: String, query: [(String, String)], body: [String: String]) async throws -> SupabaseSession {
        var request = URLRequest(url: config.url.appendingPathComponent("auth/v1/\(path)").appendingQuery(query.map { URLQueryItem(name: $0.0, value: $0.1) }))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await transport.data(for: request)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        let expiry = response.expires_at.map { Date(timeIntervalSince1970: $0) } ?? now().addingTimeInterval(response.expires_in ?? 3600)
        return SupabaseSession(
            accessToken: response.access_token, refreshToken: response.refresh_token,
            expiresAt: expiry, userID: response.user?.id ?? session?.userID ?? ""
        )
    }

    // MARK: - REST

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func request(_ method: String, _ table: String, query: [(String, String)]) async throws -> URLRequest {
        let url = config.url.appendingPathComponent("rest/v1/\(table)").appendingQuery(query.map { URLQueryItem(name: $0.0, value: $0.1) })
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func fetch<T: Decodable>(_ table: String, query: [(String, String)]) async throws -> T {
        let data = try await send(request("GET", table, query: query))
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
    }

    func rest<B: Encodable>(_ method: String, _ table: String, query: [(String, String)] = [], body: B?, prefer: String = "return=minimal") async throws {
        var request = try await request(method, table, query: query)
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        _ = try await send(request)
    }

    /// Sends a request, re-authenticating once if the token was rejected.
    func send(_ request: URLRequest) async throws -> Data {
        do {
            return try await transport.data(for: request)
        } catch HTTPError.status(401, _) {
            setSession(nil)
            var retry = request
            retry.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
            return try await transport.data(for: retry)
        } catch HTTPError.status(409, let body) {
            // Unique violation (join code taken): callers retry with a new code.
            throw HTTPError.status(409, body)
        } catch HTTPError.status(let code, let body) {
            throw MatchServiceError.server(Self.message(from: body) ?? "Server error \(code)")
        }
    }

    static func message(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return json.first("message", "msg", "error_description", "error")?.string
    }
}
