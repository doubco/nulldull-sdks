import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Waits the given number of milliseconds between retries. Must throw when the task is
/// cancelled. Replace it in tests to record the requested delays without waiting.
public typealias NullDullSleep = @Sendable (_ milliseconds: Int) async throws -> Void

/// Retry-After values above this (seconds) are raised instead of waited for (SPEC.md section 6).
public let maxRetryAfterSeconds = 30

let defaultSleep: NullDullSleep = { milliseconds in
    try await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
}

private let retryableStatuses: Set<Int> = [429, 502, 503, 504]

/// `500 ms × 2^(n−1)` before retry `n`: 500 ms, then 1000 ms. No jitter.
func backoff(_ retry: Int) -> Int { 500 << (retry - 1) }

// MARK: - Query strings

/// Ordered query parameters. Absent values are left out and lists repeat the key.
struct Query: Sendable {
    private(set) var items: [(name: String, value: String)] = []

    mutating func add(_ name: String, _ value: String?) {
        if let value { items.append((name, value)) }
    }

    mutating func add(_ name: String, _ value: Int?) {
        if let value { items.append((name, String(value))) }
    }

    mutating func add(_ name: String, repeating values: [String]) {
        for value in values { items.append((name, value)) }
    }

    var string: String {
        guard !items.isEmpty else { return "" }
        return "?" + items.map { "\(percentEncode($0.name))=\(percentEncode($0.value))" }.joined(separator: "&")
    }
}

/// `encodeURIComponent` semantics: everything except `A–Z a–z 0–9 - _ . ! ~ * ' ( )` is escaped.
private let uriComponentAllowed: CharacterSet = {
    var set = CharacterSet()
    set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    return set
}()

func percentEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed) ?? value
}

// MARK: - Origins

/// Scheme, host and effective port. Hosts compare case-insensitively; default ports equal omitted ones.
struct Origin: Hashable, Sendable {
    let scheme: String
    let host: String
    let port: Int

    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        if let port = url.port {
            self.port = port
        } else if scheme == "https" {
            self.port = 443
        } else if scheme == "http" {
            self.port = 80
        } else {
            self.port = -1
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if port != Self.defaultPort(scheme) { components.port = port }
        return components.url!
    }

    static func defaultPort(_ scheme: String) -> Int {
        switch scheme {
        case "https": 443
        case "http": 80
        default: -1
        }
    }
}

// MARK: - Response parsing

private func header(_ response: HTTPURLResponse, _ name: String) -> String? {
    guard let value = response.value(forHTTPHeaderField: name), !value.isEmpty else { return nil }
    return value
}

private func requestID(_ response: HTTPURLResponse) -> String? {
    header(response, "X-Request-Id") ?? header(response, "CF-Ray")
}

private let httpDateFormats = [
    "EEE, dd MMM yyyy HH:mm:ss zzz",  // RFC 1123
    "EEEE, dd-MMM-yy HH:mm:ss zzz",  // RFC 850
    "EEE MMM d HH:mm:ss yyyy",  // asctime
]

/// Seconds from a `Retry-After` header (delta-seconds or an HTTP date), or nil.
func parseRetryAfter(_ value: String?, now: Date = Date()) -> Int? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) {
        return Int(trimmed) ?? Int.max
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    for format in httpDateFormats {
        formatter.dateFormat = format
        if let date = formatter.date(from: trimmed) {
            return max(0, Int((date.timeIntervalSince(now)).rounded(.up)))
        }
    }
    return nil
}

private func firstMatch(_ pattern: String, in value: String) -> [String?]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(value.startIndex..., in: value)
    guard let match = regex.firstMatch(in: value, range: range) else { return nil }
    return (0..<match.numberOfRanges).map { index in
        Range(match.range(at: index), in: value).map { String(value[$0]) }
    }
}

/// File name from `Content-Disposition`: RFC 5987 `filename*` first, then `filename`.
func parseFilename(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    if let groups = firstMatch(#"filename\*\s*=\s*([^']*)'[^']*'([^;]+)"#, in: value),
        let encoded = groups[2]?.trimmingCharacters(in: .whitespaces), !encoded.isEmpty,
        let decoded = encoded.removingPercentEncoding
    {
        return decoded
    }
    if let groups = firstMatch(#"(?:^|;)\s*filename\s*=\s*"((?:[^"\\]|\\.)*)""#, in: value), let quoted = groups[1] {
        var result = ""
        var escaping = false
        for character in quoted {
            if escaping {
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }
    if let groups = firstMatch(#"(?:^|;)\s*filename\s*=\s*([^;]+)"#, in: value), let plain = groups[1] {
        let trimmed = plain.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
    return nil
}

private func errorFrom(_ data: Data, _ response: HTTPURLResponse) -> NullDullError {
    // Not JSON: a router page, a gateway error or an empty body.
    let body = (try? JSONDecoder().decode(JSONValue.self, from: data))?.objectValue
    let code = body?["code"]?.stringValue ?? NullDullError.Code.requestFailed.rawValue
    return NullDullError(
        status: response.statusCode,
        code: NullDullError.Code(code),
        message: body?["message"]?.stringValue,
        detail: body?["detail"]?.stringValue,
        requestID: requestID(response),
        retryAfter: parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After")),
        body: body
    )
}

// MARK: - Requester

/// Sends GET requests with the SDK's headers, retries, timeout and error mapping.
struct Requester: Sendable {
    let apiKey: String
    /// `baseURL` without a trailing slash; paths are appended as given.
    let baseURL: String
    let origin: Origin
    let timeout: TimeInterval
    let maxRetries: Int
    let transport: any NullDullTransport
    let userAgent: String
    let sleep: NullDullSleep

    /// GETs a JSON resource under `baseURL` and decodes it, optionally rewriting the JSON first.
    func json<T: Decodable>(
        _ path: String,
        _ query: Query = Query(),
        as type: T.Type = T.self,
        transform: (@Sendable (JSONValue) throws -> JSONValue)? = nil
    ) async throws -> T {
        let url = try makeURL(path, query)
        let (data, response) = try await send(url, accept: "application/json", authorize: true)
        let decoder = JSONDecoder()
        let source: Data
        if let transform {
            let value: JSONValue
            do {
                value = try decoder.decode(JSONValue.self, from: data)
            } catch {
                throw invalidJSON(response, error)
            }
            source = try JSONEncoder().encode(try transform(value))
        } else {
            source = data
        }
        do {
            return try decoder.decode(T.self, from: source)
        } catch let error as DecodingError {
            if case .dataCorrupted = error, (try? decoder.decode(JSONValue.self, from: source)) == nil {
                throw invalidJSON(response, error)
            }
            throw NullDullError(
                status: response.statusCode,
                code: .invalidResponse,
                message: "NullDull returned JSON in an unexpected shape: \(error)",
                requestID: requestID(response),
                underlyingError: error
            )
        }
    }

    private func invalidJSON(_ response: HTTPURLResponse, _ error: any Error & Sendable) -> NullDullError {
        NullDullError(
            status: response.statusCode,
            code: .invalidResponse,
            message: "NullDull returned a response that is not valid JSON.",
            requestID: requestID(response),
            underlyingError: error
        )
    }

    /// GETs bytes from a path under `baseURL`.
    func download(_ path: String, _ query: Query) async throws -> Download {
        try await download(url: makeURL(path, query), authorize: true)
    }

    /// GETs bytes from an absolute URL, sending `Authorization` only when `authorize` is true.
    func download(url: URL, authorize: Bool) async throws -> Download {
        let (data, response) = try await send(url, accept: "*/*", authorize: authorize)
        return Download(
            bytes: data,
            contentType: header(response, "Content-Type"),
            filename: parseFilename(response.value(forHTTPHeaderField: "Content-Disposition"))
        )
    }

    private func makeURL(_ path: String, _ query: Query) throws -> URL {
        guard let url = URL(string: baseURL + path + query.string) else {
            throw NullDullError.invalidArgument("Could not build a request URL.")
        }
        return url
    }

    private func send(_ url: URL, accept: String, authorize: Bool) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = timeout > 0 ? timeout : 7 * 24 * 60 * 60
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if authorize { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var retry = 0
        while true {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await attempt(request)
            } catch let error as NullDullError where error.code == .networkError && retry < maxRetries {
                retry += 1
                try await wait(backoff(retry))
                continue
            }
            if (200..<300).contains(response.statusCode) { return (data, response) }
            let error = errorFrom(data, response)
            guard retryableStatuses.contains(response.statusCode), retry < maxRetries else { throw error }
            if let retryAfter = error.retryAfter, retryAfter > maxRetryAfterSeconds { throw error }
            retry += 1
            // The failed attempt's body is discarded here.
            try await wait(error.retryAfter.map { $0 * 1000 } ?? backoff(retry))
        }
    }

    private func wait(_ milliseconds: Int) async throws {
        do {
            try await sleep(milliseconds)
        } catch {
            throw NullDullError.aborted(error)
        }
        if Task.isCancelled { throw NullDullError.aborted() }
    }

    /// One attempt: the transport call, raced against the timeout and task cancellation.
    private func attempt(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if Task.isCancelled { throw NullDullError.aborted() }
        let transport = self.transport
        do {
            return try await race(timeout: timeout) { try await transport.send(request) }
        } catch let error as NullDullError {
            throw error
        } catch is TimeoutSignal {
            throw NullDullError.client(.timeout, "The request timed out after \(Int(timeout * 1000)) ms.")
        } catch {
            if Task.isCancelled || error is CancellationError { throw NullDullError.aborted(error) }
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw NullDullError.client(.timeout, "The request timed out.", underlying: urlError)
            }
            throw NullDullError.client(.networkError, "The request could not reach NullDull.", underlying: error)
        }
    }
}

// MARK: - Racing an operation against a timeout and cancellation

struct TimeoutSignal: Error {}

/// Runs `operation`, but returns as soon as the timeout fires or the calling task is cancelled,
/// even when the operation itself does not respond to cancellation.
func race<T: Sendable>(
    timeout: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let state = RaceState<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
            state.start(continuation, timeout: timeout, operation)
        }
    } onCancel: {
        state.finish(.failure(CancellationError()))
    }
}

private final class RaceState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var finished: Result<T, any Error>?
    private var tasks: [Task<Void, Never>] = []

    func start(
        _ continuation: CheckedContinuation<T, any Error>,
        timeout: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) {
        lock.lock()
        if let finished {
            // Cancelled before the race started.
            lock.unlock()
            continuation.resume(with: finished)
            return
        }
        self.continuation = continuation
        tasks.append(Task { [self] in
            do {
                finish(.success(try await operation()))
            } catch {
                finish(.failure(error))
            }
        })
        if timeout > 0 {
            tasks.append(Task { [self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !Task.isCancelled { finish(.failure(TimeoutSignal())) }
            })
        }
        lock.unlock()
    }

    func finish(_ result: Result<T, any Error>) {
        lock.lock()
        guard finished == nil else {
            lock.unlock()
            return
        }
        finished = result
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()
        for task in tasks { task.cancel() }
        continuation?.resume(with: result)
    }
}
