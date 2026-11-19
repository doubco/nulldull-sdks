import Foundation

/// A folder filter for ``MemoryAPI``.
///
/// Pass `nil` (the default) for no folder filter, ``root`` for items at the location root
/// (sent as the literal `root`), or a folder ID. String literals work as IDs:
/// `folderID: "7c9e6679-…"`.
public enum FolderFilter: Sendable, Hashable, ExpressibleByStringLiteral {
    /// Items directly at the location root: unfiled documents and assets, or top-level folders.
    case root
    /// Items directly inside this folder.
    case id(String)

    public init(stringLiteral value: String) { self = .id(value) }

    var wireValue: String {
        switch self {
        case .root: "root"
        case .id(let id): id
        }
    }
}

/// Read-only Memory (`memory:read`). Needs a private key and a workspace ID.
///
/// ```swift
/// let client = try NullDullClient(apiKey: "nd_sec_…", workspaceID: "…")
/// for try await document in client.memory.iterateDocuments(tags: ["rules"]) {
///     print(document.name)
/// }
/// ```
public struct MemoryAPI: Sendable {
    let requester: Requester
    let access: WorkspaceAccess

    private func get<T: Decodable>(_ path: String, _ query: Query = Query(), as type: T.Type = T.self) async throws -> T {
        try await requester.json(try access.root() + path, query, as: T.self)
    }

    // MARK: Scopes

    /// Locations the key's member can see (workspace root, products, projects).
    public func listScopes(after: String? = nil) async throws -> Page<Scope> {
        var query = Query()
        query.add("after", after)
        return try await get("/scopes", query)
    }

    /// Every visible location, lazily across pages.
    public func iterateScopes(after: String? = nil) -> AsyncThrowingStream<Scope, any Error> {
        paginate(start: after) { cursor in
            let page = try await listScopes(after: cursor)
            return (page.items, page.nextCursor)
        }
    }

    // MARK: Folders

    /// Readable folders, optionally in one location or under one parent.
    ///
    /// - Parameters:
    ///   - scopeID: Only folders in this location.
    ///   - parentID: A parent folder, ``FolderFilter/root`` for top-level folders, or `nil` for every readable folder.
    ///   - after: A cursor from ``FolderList/nextCursor``.
    public func listFolders(scopeID: String? = nil, parentID: FolderFilter? = nil, after: String? = nil) async throws
        -> FolderList
    {
        var query = Query()
        query.add("scopeId", scopeID)
        query.add("parentId", parentID?.wireValue)
        query.add("after", after)
        return try await get("/folders", query)
    }

    /// Every readable folder matching the filters, lazily across pages.
    public func iterateFolders(scopeID: String? = nil, parentID: FolderFilter? = nil, after: String? = nil)
        -> AsyncThrowingStream<FolderSummary, any Error>
    {
        paginate(start: after) { cursor in
            let page = try await listFolders(scopeID: scopeID, parentID: parentID, after: cursor)
            return (page.items, page.nextCursor)
        }
    }

    /// A folder with its ancestors and effective placement. A missing or unreadable folder is `403 FORBIDDEN`.
    public func getFolder(_ folderID: String) async throws -> Folder {
        try await get("/folders/\(try pathSegment(folderID, "folderID"))")
    }

    // MARK: Documents

    /// Readable documents (Markdown files) without their content.
    ///
    /// - Parameters:
    ///   - scopeID: Only documents in this location.
    ///   - folderID: A folder, ``FolderFilter/root`` for unfiled documents, or `nil` for every folder.
    ///   - tags: Every listed tag must be present (sent as repeated `tag`).
    ///   - kind: Only documents with this kind label. Sent as given; the server validates it.
    ///   - lifecycle: Only documents with this lifecycle label.
    ///   - after: A cursor from ``Page/nextCursor``.
    public func listDocuments(
        scopeID: String? = nil,
        folderID: FolderFilter? = nil,
        tags: [String] = [],
        kind: FileKind? = nil,
        lifecycle: FileLifecycle? = nil,
        after: String? = nil
    ) async throws -> Page<DocumentSummary> {
        var query = Query()
        query.add("scopeId", scopeID)
        query.add("folderId", folderID?.wireValue)
        query.add("tag", repeating: tags)
        query.add("kind", kind?.rawValue)
        query.add("lifecycle", lifecycle?.rawValue)
        query.add("after", after)
        return try await get("/documents", query)
    }

    /// Every readable document matching the filters, lazily across pages.
    public func iterateDocuments(
        scopeID: String? = nil,
        folderID: FolderFilter? = nil,
        tags: [String] = [],
        kind: FileKind? = nil,
        lifecycle: FileLifecycle? = nil,
        after: String? = nil
    ) -> AsyncThrowingStream<DocumentSummary, any Error> {
        paginate(start: after) { cursor in
            let page = try await listDocuments(
                scopeID: scopeID, folderID: folderID, tags: tags, kind: kind, lifecycle: lifecycle, after: cursor)
            return (page.items, page.nextCursor)
        }
    }

    /// A document with its saved Markdown ``Document/content``. A missing or unreadable document is `403 FORBIDDEN`.
    public func getDocument(_ documentID: String) async throws -> Document {
        try await get("/documents/\(try pathSegment(documentID, "documentID"))")
    }

    /// Resolves a relative Markdown link inside a document to another readable document.
    public func resolveLink(_ documentID: String, href: String) async throws -> LinkResolution {
        var query = Query()
        query.add("href", href)
        return try await get("/documents/\(try pathSegment(documentID, "documentID"))/resolve-link", query)
    }

    // MARK: Search and tags

    /// Literal, case-insensitive search (2–160 characters) over names, content and tags.
    /// Shorter queries get `400 INVALID_INPUT` from the server.
    public func search(
        _ q: String,
        scopeID: String? = nil,
        tags: [String] = [],
        kind: FileKind? = nil,
        lifecycle: FileLifecycle? = nil,
        after: String? = nil
    ) async throws -> Page<SearchResult> {
        var query = Query()
        query.add("q", q)
        query.add("scopeId", scopeID)
        query.add("tag", repeating: tags)
        query.add("kind", kind?.rawValue)
        query.add("lifecycle", lifecycle?.rawValue)
        query.add("after", after)
        return try await get("/search", query)
    }

    /// Every search hit, lazily across pages.
    public func iterateSearch(
        _ q: String,
        scopeID: String? = nil,
        tags: [String] = [],
        kind: FileKind? = nil,
        lifecycle: FileLifecycle? = nil,
        after: String? = nil
    ) -> AsyncThrowingStream<SearchResult, any Error> {
        paginate(start: after) { cursor in
            let page = try await search(q, scopeID: scopeID, tags: tags, kind: kind, lifecycle: lifecycle, after: cursor)
            return (page.items, page.nextCursor)
        }
    }

    /// Tags on readable documents with their counts, most used first.
    ///
    /// - Parameters:
    ///   - scopeID: Only tags on documents in this location.
    ///   - q: A substring of the tag, up to 48 characters.
    ///   - after: A cursor from ``Page/nextCursor``.
    public func listTags(scopeID: String? = nil, q: String? = nil, after: String? = nil) async throws -> Page<TagCount> {
        var query = Query()
        query.add("scopeId", scopeID)
        query.add("q", q)
        query.add("after", after)
        return try await get("/tags", query)
    }

    /// Every tag, lazily across pages.
    public func iterateTags(scopeID: String? = nil, q: String? = nil, after: String? = nil)
        -> AsyncThrowingStream<TagCount, any Error>
    {
        paginate(start: after) { cursor in
            let page = try await listTags(scopeID: scopeID, q: q, after: cursor)
            return (page.items, page.nextCursor)
        }
    }

    // MARK: Assets

    /// Readable Memory assets with metadata.
    ///
    /// - Parameters:
    ///   - scopeID: Only assets in this location.
    ///   - folderID: A folder, ``FolderFilter/root`` for unfiled assets, or `nil` for every folder.
    ///   - q: A substring of name, description or tags, up to 160 characters.
    ///   - tags: Every listed tag must be present (sent as repeated `tag`).
    ///   - after: A cursor from ``Page/nextCursor``.
    public func listAssets(
        scopeID: String? = nil,
        folderID: FolderFilter? = nil,
        q: String? = nil,
        tags: [String] = [],
        after: String? = nil
    ) async throws -> Page<Asset> {
        var query = Query()
        query.add("scopeId", scopeID)
        query.add("folderId", folderID?.wireValue)
        query.add("q", q)
        query.add("tag", repeating: tags)
        query.add("after", after)
        return try await get("/assets", query)
    }

    /// Every readable asset matching the filters, lazily across pages.
    public func iterateAssets(
        scopeID: String? = nil,
        folderID: FolderFilter? = nil,
        q: String? = nil,
        tags: [String] = [],
        after: String? = nil
    ) -> AsyncThrowingStream<Asset, any Error> {
        paginate(start: after) { cursor in
            let page = try await listAssets(scopeID: scopeID, folderID: folderID, q: q, tags: tags, after: cursor)
            return (page.items, page.nextCursor)
        }
    }

    /// An asset's metadata and current object (filename, media type, SHA-256).
    ///
    /// - Parameters:
    ///   - assetID: The asset.
    ///   - revisionID: A specific immutable version instead of the current one.
    public func getAsset(_ assetID: String, revisionID: String? = nil) async throws -> Asset {
        var query = Query()
        query.add("revisionId", revisionID)
        return try await get("/assets/\(try pathSegment(assetID, "assetID"))", query)
    }

    /// An asset's immutable versions, newest first.
    public func listAssetVersions(_ assetID: String, after: String? = nil) async throws -> Page<AssetVersion> {
        var query = Query()
        query.add("after", after)
        return try await get("/assets/\(try pathSegment(assetID, "assetID"))/versions", query)
    }

    /// Every version of an asset, newest first, lazily across pages.
    public func iterateAssetVersions(_ assetID: String, after: String? = nil)
        -> AsyncThrowingStream<AssetVersion, any Error>
    {
        paginate(start: after) { cursor in
            let page = try await listAssetVersions(assetID, after: cursor)
            return (page.items, page.nextCursor)
        }
    }

    /// Downloads an asset's bytes, or a resized preview.
    ///
    /// - Parameters:
    ///   - assetID: The asset.
    ///   - revisionID: A specific version instead of the current one.
    ///   - preview: Serve images inline (`preview=true`). Implied by `width`.
    ///   - width: Resized WebP width in pixels for PNG, JPEG, WebP and AVIF. The server rounds up to
    ///     64, 128, 256, 512, 1024 or 2048; other types and wider requests return the original.
    public func downloadAsset(_ assetID: String, revisionID: String? = nil, preview: Bool = false, width: Int? = nil)
        async throws -> Download
    {
        if let width, width < 1 { throw NullDullError.invalidArgument("width must be a positive whole number of pixels.") }
        let path = try access.root() + "/assets/\(try pathSegment(assetID, "assetID"))/download"
        var query = Query()
        query.add("revisionId", revisionID)
        query.add("preview", preview || width != nil ? "true" : nil)
        query.add("w", width)
        return try await requester.download(path, query)
    }
}

/// Checks the preconditions of `memory` and `locale` calls before any request.
struct WorkspaceAccess: Sendable {
    let workspaceID: String?
    let isPublicKey: Bool

    /// The platform path prefix for the workspace.
    func root() throws -> String {
        if isPublicKey {
            throw NullDullError.client(
                .privateKeyRequired, "Memory and Locale need a private key (nd_sec_…) with the matching scope.")
        }
        guard let workspaceID else {
            throw NullDullError.client(
                .workspaceRequired, "Memory and Locale need workspaceID: a key cannot look up its own workspace.")
        }
        return "/api/platform/workspaces/\(percentEncode(workspaceID))"
    }
}
