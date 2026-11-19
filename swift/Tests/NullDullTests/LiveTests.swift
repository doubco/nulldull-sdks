import Foundation
import Testing

import NullDull

/// Optional live tests against a real NullDull API, skipped unless the variables are set:
///
/// - `NULLDULL_PUBLIC_KEY` + `NULLDULL_GRID_POOL`: Grid delivery
/// - `NULLDULL_PRIVATE_KEY` + `NULLDULL_WORKSPACE_ID`: Memory and Locale
/// - `NULLDULL_LOCALE_SCOPE_ID` (optional): Locale export location (default: workspace root)
/// - `NULLDULL_BASE_URL` (optional): default `https://nulldull.com`
///
/// Never print key values.
enum Live {
    static let env = ProcessInfo.processInfo.environment
    static func value(_ name: String) -> String? { env[name].flatMap { $0.isEmpty ? nil : $0 } }

    static let baseURL = value("NULLDULL_BASE_URL").flatMap(URL.init(string:)) ?? NullDullClient.defaultBaseURL
    static let grid = value("NULLDULL_PUBLIC_KEY") != nil && value("NULLDULL_GRID_POOL") != nil
    static let platform = value("NULLDULL_PRIVATE_KEY") != nil && value("NULLDULL_WORKSPACE_ID") != nil
}

@Suite("Live Grid", .enabled(if: Live.grid, "Set NULLDULL_PUBLIC_KEY and NULLDULL_GRID_POOL"))
struct LiveGridTests {
    let pool = Live.value("NULLDULL_GRID_POOL") ?? ""
    func client() throws -> NullDullClient {
        try NullDullClient(apiKey: Live.value("NULLDULL_PUBLIC_KEY") ?? "", baseURL: Live.baseURL)
    }

    @Test func listsIteratesAndReadsPublishedPages() async throws {
        let list = try await client().grid.listPages(pool, limit: 2)
        #expect(list.pool.key == pool)
        var count = 0
        for try await summary in try client().grid.iteratePages(pool, limit: 2) {
            #expect(!summary.slug.isEmpty)
            count += 1
            if count >= 5 { break }
        }
        print("Live Grid: \(list.items.count) page(s) on the first page, \(count) iterated")
        guard let first = list.items.first else { return }
        let page = try await client().grid.getPage(pool, slug: first.slug, locale: first.locale)
        print("Live Grid: page with \(page.document.nodes.count) node(s) and \(page.assets.count) asset(s)")
        #expect(page.id == first.id)
        #expect(page.document.json["nodes"]?.arrayValue != nil)
        for asset in page.assets {
            #expect(asset.url.hasPrefix("http"))
            #expect(asset.url.contains("key="))
        }
    }

    @Test func downloadsACover() async throws {
        let list = try await client().grid.listPages(pool, limit: 10)
        guard let cover = list.items.compactMap(\.cover).first else { return }
        let download = try await client().grid.downloadAsset(cover)
        print("Live Grid: downloaded a \(download.size)-byte cover (\(download.contentType ?? "no type"))")
        #expect(download.size == Int(cover.byteSize))
        #expect(download.size > 0)
    }

    @Test func raisesNotFoundForAMissingPage() async throws {
        let error = await failure { _ = try await client().grid.getPage(pool, slug: "nulldull-sdk-live-test-missing-page") }
        #expect(error.status == 404)
        #expect(error.code == .notFound)
        #expect(error.requestID != nil)
    }

    @Test func neverFollowsARedirect() async throws {
        // If the plain-HTTP origin redirects to HTTPS, the SDK must refuse instead of following it.
        guard var components = URLComponents(url: Live.baseURL, resolvingAgainstBaseURL: false), components.scheme == "https"
        else { return }
        components.scheme = "http"
        let client = try NullDullClient(apiKey: Live.value("NULLDULL_PUBLIC_KEY") ?? "", baseURL: components.url!)
        do {
            _ = try await client.grid.listPages(pool, limit: 1)
            print("Live Grid: the HTTP origin answered without a redirect")
        } catch let error as NullDullError where (300..<400).contains(error.status) {
            #expect(error.code == .requestFailed)
            print("Live Grid: refused a \(error.status) redirect from the HTTP origin")
        }
    }

    @Test func refusesThePlatformAPIForAPublicKey() async throws {
        let client = try NullDullClient(apiKey: Live.value("NULLDULL_PUBLIC_KEY") ?? "", workspaceID: "w", baseURL: Live.baseURL)
        #expect(await failure { _ = try await client.memory.listScopes() }.code == .privateKeyRequired)
    }
}

@Suite("Live Memory and Locale", .enabled(if: Live.platform, "Set NULLDULL_PRIVATE_KEY and NULLDULL_WORKSPACE_ID"))
struct LivePlatformTests {
    let workspace = Live.value("NULLDULL_WORKSPACE_ID") ?? ""
    func client() throws -> NullDullClient {
        try NullDullClient(apiKey: Live.value("NULLDULL_PRIVATE_KEY") ?? "", workspaceID: workspace, baseURL: Live.baseURL)
    }

    /// A key without `memory:read` or `locale:read` gets 403; that is configuration, not an SDK failure.
    private func tolerateForbidden<T>(_ call: () async throws -> T) async throws -> T? {
        do {
            return try await call()
        } catch let error as NullDullError where error.code == .forbidden {
            return nil
        }
    }

    @Test func listsScopesDocumentsSearchAndTags() async throws {
        guard let scopes = try await tolerateForbidden({ try await client().memory.listScopes() }) else { return }
        #expect(scopes.items.contains { $0.id == workspace })
        let documents = try await client().memory.listDocuments()
        if let first = documents.items.first {
            #expect(try await client().memory.getDocument(first.id).id == first.id)
        }
        _ = try await client().memory.listTags()
        _ = try await client().memory.search("the")
    }

    @Test func listsLocaleFormatsAndExports() async throws {
        guard let formats = try await tolerateForbidden({ try await client().locale.listFormats() }) else { return }
        #expect(formats.items.map(\.id).contains(.json))
        let scope = Live.value("NULLDULL_LOCALE_SCOPE_ID") ?? workspace
        if let exported = try await tolerateForbidden({ try await client().locale.export(scopeID: scope) }) {
            #expect(exported.format == .json)
        }
    }
}
