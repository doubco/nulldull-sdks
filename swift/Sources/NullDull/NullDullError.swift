import Foundation

/// The one error type every NullDull call throws.
///
/// `status` is the HTTP status, or `0` for client-side errors raised before or without a
/// response. `code` is the API's error code (for example ``Code/forbidden``) or one of the
/// client codes (``Code/invalidArgument``, ``Code/timeout``, …).
///
/// ```swift
/// do {
///     let page = try await client.grid.getPage("my-blog", slug: "hello-world")
/// } catch let error as NullDullError where error.code == .notFound {
///     // Unpublished or withdrawn.
/// }
/// ```
public struct NullDullError: Error, Sendable, CustomStringConvertible, LocalizedError {
    /// The HTTP status, or `0` for client-side errors.
    public let status: Int
    /// The response body's `code`, or a client code.
    public let code: Code
    /// The body's `message`, or `NullDull request failed (<status> <code>).`
    public let message: String
    /// The body's `detail`, for example `LOCALE_EXPORT_TOO_LARGE`.
    public let detail: String?
    /// The `X-Request-Id` response header, or else `CF-Ray`.
    public let requestID: String?
    /// `Retry-After` in seconds, when the response had one.
    public let retryAfter: Int?
    /// The whole decoded JSON error body. Locale errors put `key`, `language` and `issues` here.
    public let body: [String: JSONValue]?
    /// The transport error behind ``Code/networkError``, ``Code/timeout`` or ``Code/aborted``, if any.
    public let underlyingError: (any Error & Sendable)?

    public init(
        status: Int,
        code: Code,
        message: String? = nil,
        detail: String? = nil,
        requestID: String? = nil,
        retryAfter: Int? = nil,
        body: [String: JSONValue]? = nil,
        underlyingError: (any Error & Sendable)? = nil
    ) {
        self.status = status
        self.code = code
        self.message = message ?? "NullDull request failed (\(status) \(code.rawValue))."
        self.detail = detail
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.body = body
        self.underlyingError = underlyingError
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}

extension NullDullError {
    /// An error code: the API's `code` string, or a client code. Unknown server codes are kept as given.
    public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public var description: String { rawValue }

        // Client codes (status 0).
        /// Bad client options or method arguments, found before any request.
        public static let invalidArgument: Code = "INVALID_ARGUMENT"
        /// A `memory` or `locale` call on a client without a workspace ID.
        public static let workspaceRequired: Code = "WORKSPACE_REQUIRED"
        /// A `memory` or `locale` call with a public key. No request is sent.
        public static let privateKeyRequired: Code = "PRIVATE_KEY_REQUIRED"
        /// The transport failed (DNS, TLS, connection reset).
        public static let networkError: Code = "NETWORK_ERROR"
        /// One attempt took longer than the client's timeout.
        public static let timeout: Code = "TIMEOUT"
        /// The calling task was cancelled.
        public static let aborted: Code = "ABORTED"
        /// A 2xx body was not valid JSON (or not the expected shape), or a cursor did not advance.
        public static let invalidResponse: Code = "INVALID_RESPONSE"
        /// A non-JSON error body, or a redirect.
        public static let requestFailed: Code = "REQUEST_FAILED"

        // Server codes.
        public static let invalidInput: Code = "INVALID_INPUT"
        public static let invalidJSON: Code = "INVALID_JSON"
        public static let unauthenticated: Code = "UNAUTHENTICATED"
        public static let invalidKey: Code = "INVALID_KEY"
        public static let keyRequired: Code = "KEY_REQUIRED"
        public static let forbidden: Code = "FORBIDDEN"
        public static let notFound: Code = "NOT_FOUND"
        public static let notAvailable: Code = "NOT_AVAILABLE"
        public static let conflict: Code = "CONFLICT"
        public static let requestTooLarge: Code = "REQUEST_TOO_LARGE"
        public static let rateLimited: Code = "RATE_LIMITED"
        public static let serviceUnavailable: Code = "SERVICE_UNAVAILABLE"
        public static let notConfigured: Code = "NOT_CONFIGURED"
    }

    static func client(_ code: Code, _ message: String, underlying: (any Error & Sendable)? = nil) -> NullDullError {
        NullDullError(status: 0, code: code, message: message, underlyingError: underlying)
    }

    static func invalidArgument(_ message: String) -> NullDullError {
        client(.invalidArgument, message)
    }

    static func aborted(_ underlying: (any Error & Sendable)? = nil) -> NullDullError {
        client(.aborted, "The request was cancelled.", underlying: underlying)
    }
}
