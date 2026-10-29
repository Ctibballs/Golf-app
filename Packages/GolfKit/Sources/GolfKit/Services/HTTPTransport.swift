import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTPError: Error, LocalizedError, Equatable {
    case invalidResponse
    case status(Int, String)
    case rateLimited
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The server sent an unexpected response."
        case .status(let code, let body): return "Server error \(code). \(body.prefix(120))"
        case .rateLimited: return "Daily API limit reached. Try again later or add a free API key in Settings."
        case .decoding(let detail): return "Couldn't read the server's data. \(detail)"
        }
    }
}

/// Abstraction over URLSession so services can be tested with canned responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: HTTPError.invalidResponse)
                }
            }
            task.resume()
        }
    }
}

extension HTTPTransport {
    /// Sends a request and returns the body, mapping error statuses.
    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200..<300: return data
        case 429: throw HTTPError.rateLimited
        default: throw HTTPError.status(response.statusCode, String(decoding: data, as: UTF8.self))
        }
    }
}

extension URL {
    func appendingQuery(_ items: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url ?? self
    }
}
