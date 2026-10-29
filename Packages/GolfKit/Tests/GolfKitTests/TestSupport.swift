import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GolfKit

/// Canned HTTP responses keyed by a matcher, recording every request.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)

    private let lock = NSLock()
    private var handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    private func record(_ request: URLRequest) -> Handler {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let handler = record(request)
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }

    var recorded: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }
}

extension URLRequest {
    var bodyString: String {
        httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func queryValue(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == name }?.value
    }
}

/// A simple 9-hole course for tests: pars 4,4,3,5,4,4,3,4,5 (par 36), stroke indexes 1...9.
func testCourse(holes: Int = 9, gameType: GameType = .golf) -> Course {
    let pars = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5]
    let infos = (0..<holes).map { HoleInfo(number: $0 + 1, par: pars[$0], strokeIndex: $0 + 1) }
    return Course(id: "test-\(holes)", name: "Test Links", gameType: gameType, holes: infos, source: .custom)
}

func round(on course: Course, strokes: [Int], putts: [Int]? = nil, date: Date = Date(), tee: TeeSet? = nil, player: UUID = UUID()) -> Round {
    let scores = strokes.enumerated().map { i, s in
        HoleScore(holeNumber: i + 1, strokes: s, putts: putts?[i])
    }
    return Round(playerID: player, playerName: "Me", course: course, tee: tee, date: date, scores: scores, isComplete: scores.count == course.holeCount)
}
