import Foundation

/// A response object from the API.
///
/// Typed properties use Swift casing (`scopeID` for the wire name `scopeId`). The original
/// object, including fields added after this SDK was released, stays reachable as ``raw``.
/// Encoding a model writes ``raw`` back unchanged, so caching and forwarding are lossless.
public protocol NullDullModel: Codable, Hashable, Sendable {
    /// The JSON object exactly as the API sent it (with Grid asset URLs made absolute).
    var raw: JSONValue { get }
}

extension NullDullModel {
    public func encode(to encoder: any Encoder) throws {
        try raw.encode(to: encoder)
    }
}

/// An enum-like string that also accepts values added by the API later, as `.unknown(value)`.
public protocol NullDullOpenEnum: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible
where RawValue == String {
    init(rawValue: String)
}

extension NullDullOpenEnum {
    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// One page of a list. Pass ``nextCursor`` back as `after` until it is `nil`.
public struct Page<Item: NullDullModel>: NullDullModel {
    public let items: [Item]
    /// The cursor for the next page, or `nil` on the last page.
    public let nextCursor: String?
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case items, nextCursor }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.req(.items)
        nextCursor = try c.opt(.nextCursor)
        raw = try JSONValue(from: decoder)
    }
}

/// A downloaded file.
public struct Download: Sendable, Hashable {
    /// The whole response body.
    public let bytes: Data
    /// The `Content-Type` header. Non-preview Memory downloads are `application/octet-stream`;
    /// the real media type is in ``AssetObject/mediaType``.
    public let contentType: String?
    /// From `Content-Disposition` (`filename*` preferred), or `nil` (for example for resized previews).
    public let filename: String?
    /// The byte length of ``bytes``.
    public var size: Int { bytes.count }

    public init(bytes: Data, contentType: String?, filename: String?) {
        self.bytes = bytes
        self.contentType = contentType
        self.filename = filename
    }
}

extension KeyedDecodingContainer {
    /// Decodes a field that is always present.
    func req<T: Decodable>(_ key: Key) throws -> T {
        try decode(T.self, forKey: key)
    }

    /// Decodes a field that may be missing or `null`.
    func opt<T: Decodable>(_ key: Key) throws -> T? {
        try decodeIfPresent(T.self, forKey: key)
    }
}
