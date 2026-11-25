import Foundation

/// A published asset (image, media, font) pinned to an exact version.
public struct PublicGridAsset: Hashable, Sendable, Codable {
  public var id: String
  public var version: Int
  /// Use exactly as returned (the client resolves it against the API origin and adds a public key).
  public var url: String
  public var filename: String
  public var mediaType: String
  public var byteSize: Int
  public var checksum: String
}

/// An optional publication cover image, independent of the page layout.
public struct PublicGridCover: Hashable, Sendable, Codable {
  public var id: String
  public var version: Int
  public var url: String
  public var filename: String
  public var mediaType: String
  public var byteSize: Int
  public var checksum: String
  /// Alternative text; empty means decorative.
  public var alt: String
}

/// List item metadata. Unknown future fields are ignored.
public struct PublicGridPageSummary: Hashable, Sendable, Codable {
  public var id: String
  public var pool: String
  public var slug: String
  public var locale: String
  public var title: String
  public var summary: String
  public var version: Int
  public var sourceVersion: Int
  /// Milliseconds since 1970.
  public var publishedAt: Double
  /// Direct parent folder captured at publication; older snapshots omit it.
  public var folderId: String?
  public var cover: PublicGridCover?

  public var publishedDate: Date { Date(timeIntervalSince1970: publishedAt / 1000) }
}

/// A published page: metadata, the validated document and its pinned asset manifest.
public struct PublicGridPage: Hashable, Sendable, Codable {
  public var summary: PublicGridPageSummary
  public var document: GridDocument
  public var assets: [PublicGridAsset]
  public var pageTargets: [String: PublishedGridPageTarget]

  public var id: String { summary.id }
  public var title: String { summary.title }
  public var slug: String { summary.slug }
  public var cover: PublicGridCover? { summary.cover }

  public init(summary: PublicGridPageSummary, document: GridDocument, assets: [PublicGridAsset]) {
    self.init(summary: summary, document: document, assets: assets, pageTargets: [:])
  }

  public init(summary: PublicGridPageSummary, document: GridDocument, assets: [PublicGridAsset],
    pageTargets: [String: PublishedGridPageTarget]) {
    self.pageTargets = pageTargets
    self.summary = summary
    self.document = document
    self.assets = assets
  }

  enum Keys: String, CodingKey { case document, assets, pageTargets }

  public init(from decoder: Decoder) throws {
    summary = try PublicGridPageSummary(from: decoder)
    let container = try decoder.container(keyedBy: Keys.self)
    document = try container.decode(GridDocument.self, forKey: .document)
    pageTargets = try container.decodeIfPresent([String: PublishedGridPageTarget].self, forKey: .pageTargets) ?? [:]
    assets = try container.decode([PublicGridAsset].self, forKey: .assets)
  }

  public func encode(to encoder: Encoder) throws {
    try summary.encode(to: encoder)
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(document, forKey: .document)
    if !pageTargets.isEmpty { try container.encode(pageTargets, forKey: .pageTargets) }
    try container.encode(assets, forKey: .assets)
  }

  /// Asset URLs by asset ID, for the renderer.
  public var assetURLs: [String: String] {
    Dictionary(assets.map { ($0.id, $0.url) }, uniquingKeysWith: { first, _ in first })
  }
}

public struct PublicGridPageList: Hashable, Sendable, Codable {
  public struct Pool: Hashable, Sendable, Codable {
    public var key: String
    public var name: String
  }
  public var pool: Pool
  public var items: [PublicGridPageSummary]
  /// Pass to the next request's `after`; `nil` on the last page.
  public var nextCursor: String?
}

public enum GridPublicArguments {
  /// `gridPublicKey`: pool keys and slugs are 1–96 lowercase letters, numbers and single hyphens.
  public static func isPublicKey(_ value: String) -> Bool {
    guard (1...96).contains(value.utf8.count) else { return false }
    let groups = value.split(separator: "-", omittingEmptySubsequences: false)
    return groups.allSatisfy { group in
      !group.isEmpty && group.utf8.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) }
    }
  }

  /// `gridPublicLocale`: a lowercase language tag such as `en` or `pt-br`.
  public static func isLocale(_ value: String) -> Bool {
    guard value.utf8.count <= 35 else { return false }
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard let language = parts.first, (2...3).contains(language.utf8.count),
      language.utf8.allSatisfy({ (0x61...0x7A).contains($0) })
    else { return false }
    return parts.dropFirst().allSatisfy { part in
      (2...8).contains(part.utf8.count) && part.utf8.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) }
    }
  }
}
