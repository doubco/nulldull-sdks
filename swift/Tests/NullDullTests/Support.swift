import Foundation
import Testing

@testable import NullDull

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Shared fixtures (read in place from the repository's fixtures/ directory)

enum Fixtures {
    /// `<repo>/fixtures`, found relative to this source file so the fixtures are never copied.
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NullDullTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // swift
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("fixtures")

    static func data(_ path: String) -> Data {
        do {
            return try Data(contentsOf: root.appendingPathComponent(path))
        } catch {
            fatalError("Missing fixture \(path): \(error)")
        }
    }

    static func json(_ path: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: data(path))
    }

    static let manifest: Manifest = try! JSONDecoder().decode(Manifest.self, from: data("manifest.json"))
}

struct Manifest: Decodable, Sendable {
    struct Config: Decodable, Sendable {
        let baseUrl: String
        let publicKey: String
        let privateKey: String
        let workspaceId: String
    }

    struct Request: Decodable, Sendable {
        let method: String
        let path: String
        let query: [String: [String]]
    }

    struct Response: Decodable, Sendable {
        let status: Int
        let headers: [String: String]?
        let bodyFile: String?
        let body: String?
        let bodyBase64: String?

        var data: Data {
            if let bodyFile { return Fixtures.data(bodyFile) }
            if let bodyBase64 { return Data(base64Encoded: bodyBase64)! }
            return Data((body ?? "").utf8)
        }
    }

    struct Exchange: Decodable, Sendable {
        let request: Request
        let response: Response
    }

    struct Check: Decodable, Sendable {
        let path: String
        let equals: JSONValue
    }

    struct DownloadExpectation: Decodable, Sendable {
        let contentType: String?
        let filename: String?
        let size: Int
        let bytesBase64: String
    }

    struct Expect: Decodable, Sendable {
        let resultFile: String?
        let except: [String]?
        let checks: [Check]?
        let itemCount: Int?
        let download: DownloadExpectation?
        let error: [String: JSONValue]?
        let attempts: Int?
        let sleeps: [Int]?
    }

    struct Call: Decodable, Sendable {
        let method: String
        let args: [JSONValue]
    }

    struct Case: Decodable, Sendable {
        let id: String
        let key: String
        let call: Call
        let exchanges: [Exchange]
        let expect: Expect
    }

    let config: Config
    let cases: [Case]
}

let config = Fixtures.manifest.config
let publicKey = config.publicKey
let privateKey = config.privateKey
let workspaceID = config.workspaceId

// MARK: - Mock transport

/// Answers with queued replies and records every request.
final class MockTransport: NullDullTransport, @unchecked Sendable {
    enum Reply: Sendable {
        case response(status: Int, headers: [String: String], body: Data)
        case failure(any Error & Sendable)
        /// Never answers on its own; only cancellation (or the client's timeout) ends it.
        case hang
    }

    private let lock = NSLock()
    private var queue: [Reply]
    private var recorded: [URLRequest] = []

    init(_ replies: [Reply] = []) {
        queue = replies
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func record(_ request: URLRequest) -> Reply? {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next = record(request)
        guard let next else {
            Issue.record("Unexpected request: GET \(request.url?.absoluteString ?? "?")")
            throw URLError(.unsupportedURL)
        }
        switch next {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (body, response)
        case .failure(let error):
            throw error
        case .hang:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw URLError(.timedOut)
        }
    }
}

extension MockTransport.Reply {
    static func json(_ value: JSONValue, status: Int = 200, headers: [String: String] = [:]) -> Self {
        .response(
            status: status,
            headers: ["Content-Type": "application/json"].merging(headers) { _, new in new },
            body: try! JSONEncoder().encode(value)
        )
    }

    static func fixture(_ path: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
        .response(
            status: status,
            headers: ["Content-Type": "application/json"].merging(headers) { _, new in new },
            body: Fixtures.data(path)
        )
    }

    static func text(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
        .response(status: status, headers: headers, body: Data(body.utf8))
    }
}

/// Records the retry delays the client asks for, without waiting.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int] = []

    var sleeps: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var sleep: NullDullSleep {
        { [self] milliseconds in record(milliseconds) }
    }

    private func record(_ milliseconds: Int) {
        lock.lock()
        recorded.append(milliseconds)
        lock.unlock()
    }
}

struct Harness {
    let client: NullDullClient
    let transport: MockTransport
    let sleeper: SleepRecorder
}

func harness(
    _ kind: String = "private",
    _ replies: [MockTransport.Reply] = [],
    workspace: String? = workspaceID,
    timeout: TimeInterval = 30,
    maxRetries: Int = 2,
    userAgent: String? = nil
) throws -> Harness {
    let transport = MockTransport(replies)
    let sleeper = SleepRecorder()
    let client = try NullDullClient(
        apiKey: kind == "public" ? publicKey : privateKey,
        workspaceID: workspace,
        baseURL: URL(string: config.baseUrl)!,
        transport: transport,
        timeout: timeout,
        maxRetries: maxRetries,
        userAgent: userAgent,
        sleep: sleeper.sleep
    )
    return Harness(client: client, transport: transport, sleeper: sleeper)
}

// MARK: - Assertions

/// Runs `body` and returns the `NullDullError` it throws, recording an issue otherwise.
func failure(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () async throws -> Void
) async -> NullDullError {
    do {
        try await body()
    } catch let error as NullDullError {
        return error
    } catch {
        Issue.record("Expected a NullDullError, got \(error)", sourceLocation: sourceLocation)
        return NullDullError(status: -1, code: "UNEXPECTED")
    }
    Issue.record("Expected a NullDullError, but the call succeeded", sourceLocation: sourceLocation)
    return NullDullError(status: -1, code: "NO_ERROR")
}

/// Query parameters as a multimap: name -> values in order.
func multimap(_ request: URLRequest) -> [String: [String]] {
    var result: [String: [String]] = [:]
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    for item in items { result[item.name, default: []].append(item.value ?? "") }
    return result
}

/// The raw query string, `?a=b` or `""`.
func search(_ request: URLRequest) -> String {
    guard let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedQuery else {
        return ""
    }
    return "?" + query
}

func percentEncodedPath(_ request: URLRequest) -> String {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.percentEncodedPath
}

extension JSONValue {
    /// The value at a dot path; numeric segments index arrays.
    func at(_ path: String) -> JSONValue? {
        path.split(separator: ".").reduce(Optional(self)) { current, part in
            guard let current else { return nil }
            if let index = Int(part), case .array = current { return current[index] }
            return current[String(part)]
        }
    }

    /// A copy without the members at the given dot paths.
    func removing(_ paths: [String]) -> JSONValue {
        paths.reduce(self) { $0.removing(path: $1.split(separator: ".").map(String.init)) }
    }

    private func removing(path: [String]) -> JSONValue {
        guard let first = path.first else { return self }
        let rest = Array(path.dropFirst())
        switch self {
        case .object(var object):
            if rest.isEmpty {
                object.removeValue(forKey: first)
            } else if let child = object[first] {
                object[first] = child.removing(path: rest)
            }
            return .object(object)
        case .array(var array):
            guard let index = Int(first), array.indices.contains(index) else { return self }
            if rest.isEmpty {
                array.remove(at: index)
            } else {
                array[index] = array[index].removing(path: rest)
            }
            return .array(array)
        default:
            return self
        }
    }
}

/// Collects every item of an async sequence.
func collect<S: AsyncSequence>(_ sequence: S) async throws -> [S.Element] {
    var items: [S.Element] = []
    for try await item in sequence { items.append(item) }
    return items
}
