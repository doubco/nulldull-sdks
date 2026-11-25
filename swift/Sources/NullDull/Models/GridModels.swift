import Foundation

/// A version-pinned asset of a published Grid page.
public struct GridAssetRef: NullDullModel {
    public let id: String
    /// The publication-pinned asset version.
    public let version: Int
    /// Absolute URL, normalized by ``GridAPI/assetURL(_:)``. Public keys get `key=` appended.
    public let url: String
    public let filename: String
    public let mediaType: String
    public let byteSize: Int64
    /// SHA-256, hex.
    public let checksum: String
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case id, version, url, filename, mediaType, byteSize, checksum }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        version = try c.req(.version)
        url = try c.req(.url)
        filename = try c.req(.filename)
        mediaType = try c.req(.mediaType)
        byteSize = try c.req(.byteSize)
        checksum = try c.req(.checksum)
        raw = try JSONValue(from: decoder)
    }
}

/// A page cover: an asset with alternative text.
public struct GridCover: NullDullModel {
    public let id: String
    public let version: Int
    /// Absolute URL, normalized by ``GridAPI/assetURL(_:)``.
    public let url: String
    public let filename: String
    public let mediaType: String
    public let byteSize: Int64
    public let checksum: String
    /// Alternative text; empty means decorative.
    public let alt: String
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case id, version, url, filename, mediaType, byteSize, checksum, alt }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        version = try c.req(.version)
        url = try c.req(.url)
        filename = try c.req(.filename)
        mediaType = try c.req(.mediaType)
        byteSize = try c.req(.byteSize)
        checksum = try c.req(.checksum)
        alt = try c.opt(.alt) ?? ""
        raw = try JSONValue(from: decoder)
    }
}

/// A published page without its document, as listed by ``GridAPI/listPages(_:locale:q:folderID:limit:after:)``.
public struct GridPageSummary: NullDullModel {
    public let id: String
    public let pool: String
    public let slug: String
    public let locale: String
    public let title: String
    public let summary: String
    /// The publication's own version.
    public let version: Int
    /// The saved editor version that was published.
    public let sourceVersion: Int
    /// Unix epoch milliseconds.
    public let publishedAt: Int64
    /// Direct parent folder at publication; older snapshots may omit it.
    public let folderID: String?
    public let cover: GridCover?
    public let raw: JSONValue

    enum CodingKeys: String, CodingKey {
        case id, pool, slug, locale, title, summary, version, sourceVersion, publishedAt, cover
        case folderID = "folderId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        pool = try c.req(.pool)
        slug = try c.req(.slug)
        locale = try c.req(.locale)
        title = try c.req(.title)
        summary = try c.req(.summary)
        version = try c.req(.version)
        sourceVersion = try c.req(.sourceVersion)
        publishedAt = try c.req(.publishedAt)
        folderID = try c.opt(.folderID)
        cover = try c.opt(.cover)
        raw = try JSONValue(from: decoder)
    }

    /// When the page was published.
    public var publishedDate: Date { Date(timeIntervalSince1970: TimeInterval(publishedAt) / 1000) }
}

/// The published Grid document, kept as opaque JSON.
///
/// Its full schema belongs to the Grid renderer (`@nulldull/grid-core`). The SDK does not
/// validate or render it. Read members with the convenience properties or ``json``, or
/// decode it into your own model with ``decode(_:)``.
public struct GridDocument: Codable, Hashable, Sendable {
    /// The whole document.
    public let json: JSONValue

    public init(json: JSONValue) { self.json = json }

    public init(from decoder: any Decoder) throws {
        json = try JSONValue(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try json.encode(to: encoder)
    }

    public var layout: [String: JSONValue] { json["layout"]?.objectValue ?? [:] }
    public var breakpoints: [JSONValue] { json["breakpoints"]?.arrayValue ?? [] }
    public var nodes: [JSONValue] { json["nodes"]?.arrayValue ?? [] }
    public var baseLayoutIndex: Int? { json["baseLayoutIndex"]?.intValue }
    public var baseLayoutName: String? { json["baseLayoutName"]?.stringValue }

    /// Decodes the document into any `Decodable` model, such as a renderer's document type.
    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try json.decode(T.self)
    }
}

/// A published page with its document and version-pinned asset manifest.
public struct GridPage: NullDullModel {
    public struct Target: Codable, Hashable, Sendable {
        public let entryId: String
        public let published: Bool
        public let pool: String
        public let slug: String
        public let locale: String
    }

    public let pageTargets: [String: Target]
    public let id: String
    public let pool: String
    public let slug: String
    public let locale: String
    public let title: String
    public let summary: String
    public let version: Int
    public let sourceVersion: Int
    /// Unix epoch milliseconds.
    public let publishedAt: Int64
    public let folderID: String?
    public let cover: GridCover?
    public let document: GridDocument
    /// Every asset the document uses, with absolute URLs.
    public let assets: [GridAssetRef]
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, pool, slug, locale, title, summary, version, sourceVersion, publishedAt, cover, document, assets, pageTargets
        case folderID = "folderId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        pool = try c.req(.pool)
        slug = try c.req(.slug)
        locale = try c.req(.locale)
        title = try c.req(.title)
        summary = try c.req(.summary)
        version = try c.req(.version)
        sourceVersion = try c.req(.sourceVersion)
        publishedAt = try c.req(.publishedAt)
        folderID = try c.opt(.folderID)
        cover = try c.opt(.cover)
        pageTargets = try c.opt(.pageTargets) ?? [:]
        document = try c.req(.document)
        assets = try c.opt(.assets) ?? []
        raw = try JSONValue(from: decoder)
    }

    public var publishedDate: Date { Date(timeIntervalSince1970: TimeInterval(publishedAt) / 1000) }
}

/// The pool a page list belongs to.
public struct GridPool: NullDullModel {
    public let key: String
    public let name: String
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case key, name }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.req(.key)
        name = try c.req(.name)
        raw = try JSONValue(from: decoder)
    }
}

/// One page of a pool's published pages, newest first.
public struct GridPageList: NullDullModel {
    public let pool: GridPool
    public let items: [GridPageSummary]
    /// The cursor for the next page, or `nil` on the last page.
    public let nextCursor: String?
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case pool, items, nextCursor }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pool = try c.req(.pool)
        items = try c.req(.items)
        nextCursor = try c.opt(.nextCursor)
        raw = try JSONValue(from: decoder)
    }
}
