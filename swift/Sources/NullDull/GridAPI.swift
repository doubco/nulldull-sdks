import Foundation

/// Published Grid content (`grid:published`). Works with public and private keys and needs no workspace ID.
///
/// ```swift
/// let client = try NullDullClient(apiKey: "nd_pub_…")
/// let list = try await client.grid.listPages("my-blog", limit: 10)
/// let page = try await client.grid.getPage("my-blog", slug: list.items[0].slug)
/// ```
public struct GridAPI: Sendable {
    let requester: Requester
    let publicKey: String?

    /// One page of a pool's published pages, newest first. Cover URLs are made absolute.
    ///
    /// - Parameters:
    ///   - pool: The pool key, such as `my-blog`.
    ///   - locale: Lowercase content language (`en`, `pt-br`). Default `en`; always sent.
    ///   - q: Literal search over titles and summaries, up to 160 characters. Sent only when non-empty.
    ///   - folderID: Only pages whose direct parent folder at publication was this folder.
    ///   - limit: 1–50 (server default 20).
    ///   - after: A cursor from ``GridPageList/nextCursor``.
    public func listPages(
        _ pool: String,
        locale: String = "en",
        q: String? = nil,
        folderID: String? = nil,
        limit: Int? = nil,
        after: String? = nil
    ) async throws -> GridPageList {
        let path = "/api/grid/v1/pools/\(try key(pool, "pool"))/pages"
        if let limit, !(1...50).contains(limit) {
            throw NullDullError.invalidArgument("limit must be a whole number from 1 to 50.")
        }
        if let folderID, folderID.isEmpty { throw NullDullError.invalidArgument("folderID must be a non-empty string.") }
        var query = Query()
        query.add("locale", try validLocale(locale))
        query.add("q", q.flatMap { $0.isEmpty ? nil : $0 })
        query.add("folderId", folderID)
        query.add("limit", limit)
        query.add("after", after.flatMap { $0.isEmpty ? nil : $0 })
        let grid = self
        return try await requester.json(path, query, as: GridPageList.self) { value in
            guard case .object(var list) = value, case .array(let items)? = list["items"] else { return value }
            list["items"] = .array(try items.map(grid.normalizeCover))
            return .object(list)
        }
    }

    /// Every published page across all pages of results, lazily. Empty pages with a cursor are followed.
    public func iteratePages(
        _ pool: String,
        locale: String = "en",
        q: String? = nil,
        folderID: String? = nil,
        limit: Int? = nil,
        after: String? = nil
    ) -> AsyncThrowingStream<GridPageSummary, any Error> {
        paginate(start: after) { cursor in
            let list = try await listPages(pool, locale: locale, q: q, folderID: folderID, limit: limit, after: cursor)
            return (list.items, list.nextCursor)
        }
    }

    /// A published page with its document and version-pinned asset manifest. Cover and asset URLs are made absolute.
    public func getPage(_ pool: String, slug: String, locale: String = "en") async throws -> GridPage {
        let path = "/api/grid/v1/pools/\(try key(pool, "pool"))/pages/\(try key(slug, "slug"))"
        var query = Query()
        query.add("locale", try validLocale(locale))
        let grid = self
        return try await requester.json(path, query, as: GridPage.self) { value in
            guard case .object = value else { return value }
            guard case .object(var page) = try grid.normalizeCover(value) else { return value }
            let assets = page["assets"]?.arrayValue ?? []
            page["assets"] = .array(try assets.map(grid.normalizeURL))
            return .object(page)
        }
    }

    /// Resolves an asset or cover URL against the API origin.
    ///
    /// For a public key and a URL on the API's own origin, adds `key=` so images, fonts and
    /// media can load without headers. Never adds a private key, never adds a key to another
    /// origin, and keeps an existing `key`.
    public func assetURL(_ url: String) throws -> URL {
        guard let parsed = URL(string: url, relativeTo: requester.origin.url)?.absoluteURL,
            let resolvedOrigin = Origin(parsed),
            var components = URLComponents(url: parsed, resolvingAgainstBaseURL: true)
        else {
            throw NullDullError.invalidArgument("Provide a valid asset URL.")
        }
        // Normalize like a WHATWG URL: lowercase scheme and host, drop a default port.
        components.scheme = resolvedOrigin.scheme
        components.host = resolvedOrigin.host
        if components.port == Origin.defaultPort(resolvedOrigin.scheme) { components.port = nil }
        if components.path.isEmpty { components.path = "/" }
        if let publicKey, resolvedOrigin == requester.origin,
            !(components.queryItems ?? []).contains(where: { $0.name == "key" })
        {
            let existing = components.percentEncodedQuery ?? ""
            components.percentEncodedQuery = (existing.isEmpty ? "" : existing + "&") + "key=" + percentEncode(publicKey)
        }
        guard let result = components.url else { throw NullDullError.invalidArgument("Provide a valid asset URL.") }
        return result
    }

    /// Downloads an asset or cover by URL. Sends the key only to the API's own origin.
    public func downloadAsset(_ url: String) async throws -> Download {
        guard !url.isEmpty else { throw NullDullError.invalidArgument("Provide an asset URL or an asset.") }
        let resolved = try assetURL(url)
        return try await requester.download(url: resolved, authorize: Origin(resolved) == requester.origin)
    }

    /// Downloads an asset or cover by URL. Sends the key only to the API's own origin.
    public func downloadAsset(_ url: URL) async throws -> Download {
        try await downloadAsset(url.absoluteString)
    }

    /// Downloads a page asset.
    public func downloadAsset(_ asset: GridAssetRef) async throws -> Download {
        try await downloadAsset(asset.url)
    }

    /// Downloads a page cover.
    public func downloadAsset(_ cover: GridCover) async throws -> Download {
        try await downloadAsset(cover.url)
    }

    // MARK: Helpers

    private func key(_ value: String, _ name: String) throws -> String {
        guard isGridKey(value) else {
            throw NullDullError.invalidArgument("\(name) must be 1–96 lowercase letters, numbers and single hyphens.")
        }
        return percentEncode(value)
    }

    private func validLocale(_ value: String) throws -> String {
        guard isGridLocale(value) else {
            throw NullDullError.invalidArgument("locale must be a lowercase language tag, such as en or pt-br.")
        }
        return value
    }

    /// Replaces `cover.url` with ``assetURL(_:)`` when the object has a cover.
    private func normalizeCover(_ value: JSONValue) throws -> JSONValue {
        guard case .object(var object) = value, let cover = object["cover"], case .object = cover else { return value }
        object["cover"] = try normalizeURL(cover)
        return .object(object)
    }

    /// Replaces `url` with ``assetURL(_:)``.
    private func normalizeURL(_ value: JSONValue) throws -> JSONValue {
        guard case .object(var object) = value, let url = object["url"]?.stringValue else { return value }
        object["url"] = .string(try assetURL(url).absoluteString)
        return .object(object)
    }
}
