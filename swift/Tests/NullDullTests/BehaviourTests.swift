import Foundation
import Testing

@testable import NullDull

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let emptyPage: JSONValue = ["items": [], "nextCursor": nil]

// MARK: - 1. Construction

@Suite("1. Construction")
struct ConstructionTests {
    private func make(
        apiKey: String = publicKey, workspaceID: String? = nil, baseURL: String = "https://nulldull.com",
        timeout: TimeInterval = 30, maxRetries: Int = 2
    ) throws {
        _ = try NullDullClient(
            apiKey: apiKey, workspaceID: workspaceID, baseURL: URL(string: baseURL)!, transport: MockTransport(),
            timeout: timeout, maxRetries: maxRetries)
    }

    @Test func rejectsMalformedKeys() async {
        for key in [
            "", "nd_pub_123", "nd_xyz_" + String(repeating: "a", count: 64), "nd_pub_" + String(repeating: "A", count: 64),
            "ndm_" + String(repeating: "a", count: 64), "nd_pub_" + String(repeating: "a", count: 65),
        ] {
            let error = await failure { try make(apiKey: key) }
            #expect(error.code == .invalidArgument)
            #expect(error.status == 0)
        }
    }

    @Test func rejectsBadBaseURLs() async {
        for url in [
            "ftp://nulldull.com", "nulldull.com", "https://user:pass@nulldull.com", "https://nulldull.com/?x=1",
            "https://nulldull.com/#top", "https://nulldull.com?", "file:///etc/passwd",
        ] {
            #expect(await failure { try make(baseURL: url) }.code == .invalidArgument, "\(url)")
        }
    }

    @Test func rejectsMalformedWorkspaceIDsTimeoutsAndRetries() async {
        #expect(await failure { try make(workspaceID: "../etc") }.code == .invalidArgument)
        #expect(await failure { try make(workspaceID: String(repeating: "a", count: 129)) }.code == .invalidArgument)
        #expect(await failure { try make(workspaceID: "") }.code == .invalidArgument)
        #expect(await failure { try make(timeout: -1) }.code == .invalidArgument)
        #expect(await failure { try make(timeout: .nan) }.code == .invalidArgument)
        #expect(await failure { try make(maxRetries: -1) }.code == .invalidArgument)
    }

    @Test func stripsTrailingSlashAndKeepsPathPrefix() async throws {
        let transport = MockTransport([.fixture("grid/page-list-last.json"), .fixture("grid/page-list-last.json")])
        let staging = try NullDullClient(
            apiKey: publicKey, baseURL: URL(string: "https://staging.nulldull.com/")!, transport: transport)
        #expect(staging.baseURL.absoluteString == "https://staging.nulldull.com")
        _ = try await staging.grid.listPages("nulldull-blog")
        _ = try await NullDullClient(
            apiKey: publicKey, baseURL: URL(string: "http://localhost:8787/proxy/")!, transport: transport
        ).grid.listPages("nulldull-blog")
        let requests = transport.requests
        #expect(requests[0].url?.absoluteString == "https://staging.nulldull.com/api/grid/v1/pools/nulldull-blog/pages?locale=en")
        #expect(requests[1].url?.absoluteString == "http://localhost:8787/proxy/api/grid/v1/pools/nulldull-blog/pages?locale=en")
    }

    @Test func defaultsAndKeyKind() throws {
        let client = try NullDullClient(apiKey: privateKey)
        #expect(client.baseURL.absoluteString == "https://nulldull.com")
        #expect(client.keyKind == .privateKey)
        #expect(client.workspaceID == nil)
        #expect(try NullDullClient(apiKey: publicKey).keyKind == .publicKey)
    }
}

// MARK: - 2. Headers

@Suite("2. Request headers")
struct HeaderTests {
    @Test func sendsAuthorizationAcceptAndUserAgent() async throws {
        let h = try harness("private", [.fixture("memory/scopes.json"), .text("x")], userAgent: "my-app/2.0")
        _ = try await h.client.memory.listScopes()
        _ = try await h.client.memory.downloadAsset("asset_1")
        let requests = h.transport.requests
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer \(privateKey)")
        #expect(requests[0].value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(requests[0].value(forHTTPHeaderField: "User-Agent") == "nulldull-sdk-swift/0.1.0 my-app/2.0")
        #expect(requests[1].value(forHTTPHeaderField: "Accept") == "*/*")
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].httpShouldHandleCookies == false)
        #expect(requests[0].cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        // No other custom headers (Grid's CORS policy only allows Authorization, Range and If-None-Match).
        #expect(Set(requests[0].allHTTPHeaderFields?.keys.map { $0.lowercased() } ?? []) == ["authorization", "accept", "user-agent"])
    }

    @Test func versionIsSDKVersion() {
        #expect(nullDullSDKVersion == "0.1.0")
    }
}

// MARK: - 3. Memory and Locale preconditions

@Suite("3. Memory and Locale preconditions")
struct PreconditionTests {
    @Test func needsWorkspaceIDWithoutRequest() async throws {
        let h = try harness("private", workspace: nil)
        #expect(await failure { _ = try await h.client.memory.listDocuments() }.code == .workspaceRequired)
        #expect(await failure { _ = try await h.client.locale.export(scopeID: workspaceID) }.code == .workspaceRequired)
        #expect(await failure { _ = try await h.client.memory.downloadAsset("a") }.code == .workspaceRequired)
        var iterator = h.client.memory.iterateDocuments().makeAsyncIterator()
        #expect(await failure { _ = try await iterator.next() }.code == .workspaceRequired)
        #expect(h.transport.requests.isEmpty)
    }

    @Test func needsPrivateKeyWithoutRequest() async throws {
        let h = try harness("public")
        #expect(await failure { _ = try await h.client.memory.getDocument("doc") }.code == .privateKeyRequired)
        #expect(await failure { _ = try await h.client.locale.listFormats() }.code == .privateKeyRequired)
        #expect(h.transport.requests.isEmpty)
    }

    @Test func percentEncodesPathSegmentsAndRejectsEmptyIDs() async throws {
        let h = try harness("private", [.fixture("memory/document.json")])
        _ = try await h.client.memory.getDocument("a/b c")
        #expect(percentEncodedPath(h.transport.requests[0]) == "/api/platform/workspaces/\(workspaceID)/documents/a%2Fb%20c")
        #expect(await failure { _ = try await h.client.memory.getDocument("") }.code == .invalidArgument)
        #expect(await failure { _ = try await h.client.memory.getAsset("") }.code == .invalidArgument)
    }
}

// MARK: - 4. Grid validation

@Suite("4. Grid validation")
struct GridValidationTests {
    @Test func validatesBeforeAnyRequest() async throws {
        let h = try harness("public")
        let grid = h.client.grid
        let calls: [@Sendable () async throws -> Void] = [
            { _ = try await grid.listPages("Bad_Pool") },
            { _ = try await grid.listPages("pool", locale: "EN") },
            { _ = try await grid.listPages("pool", locale: "e") },
            { _ = try await grid.listPages("pool", locale: "") },
            { _ = try await grid.listPages("pool", limit: 0) },
            { _ = try await grid.listPages("pool", limit: 51) },
            { _ = try await grid.listPages("pool", folderID: "") },
            { _ = try await grid.listPages("-pool") },
            { _ = try await grid.getPage("pool", slug: "a--b") },
            { _ = try await grid.getPage("pool", slug: String(repeating: "x", count: 97)) },
            { _ = try await grid.getPage("pool", slug: "ok", locale: "pt_BR") },
        ]
        for call in calls { #expect(await failure { try await call() }.code == .invalidArgument) }
        #expect(h.transport.requests.isEmpty)
        #expect(isGridKey(String(repeating: "x", count: 96)))
        #expect(isGridLocale("pt-br"))
        #expect(isGridLocale("zh-hant-tw"))
    }

    @Test func alwaysSendsLocaleAndOmitsEmptyQ() async throws {
        let h = try harness("public", [.fixture("grid/page-list-last.json"), .fixture("grid/page.json")])
        _ = try await h.client.grid.listPages("nulldull-blog", q: "", after: "")
        _ = try await h.client.grid.getPage("nulldull-blog", slug: "hello", locale: "pt-br")
        #expect(search(h.transport.requests[0]) == "?locale=en")
        #expect(search(h.transport.requests[1]) == "?locale=pt-br")
    }
}

// MARK: - 5. grid.assetURL

@Suite("5. grid.assetURL")
struct AssetURLTests {
    let pub = try! harness("public").client.grid
    let sec = try! harness("private").client.grid

    @Test func resolvesRelativeURLsAndAddsPublicKeyOnAPIOrigin() throws {
        #expect(
            try pub.assetURL("/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3").absoluteString
                == "https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3&key=\(publicKey)")
        #expect(try pub.assetURL("https://NULLDULL.com:443/x").absoluteString == "https://nulldull.com/x?key=\(publicKey)")
        #expect(try pub.assetURL("https://nulldull.com").absoluteString == "https://nulldull.com/?key=\(publicKey)")
    }

    @Test func keepsAnExistingKey() throws {
        #expect(try pub.assetURL("/x?key=nd_pub_existing").absoluteString == "https://nulldull.com/x?key=nd_pub_existing")
    }

    @Test func neverAddsAKeyToAnotherOrigin() throws {
        for url in [
            "https://cdn.example.com/a.png", "//evil.example/a.png", "https://nulldull.com.evil.example/a.png",
            "http://nulldull.com/a.png", "https://nulldull.com:8443/a.png", "https://evil.example/?u=https://nulldull.com",
        ] {
            #expect(!(try pub.assetURL(url).absoluteString.contains("key=")), "\(url)")
        }
        #expect(try pub.assetURL("//evil.example/a.png").absoluteString == "https://evil.example/a.png")
    }

    @Test func neverAddsAPrivateKey() throws {
        #expect(
            try sec.assetURL("/api/grid/v1/pools/p/pages/s/assets/a?version=1").absoluteString
                == "https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?version=1")
    }

    @Test func resolvesAgainstTheOriginNotThePath() throws {
        let client = try NullDullClient(
            apiKey: publicKey, baseURL: URL(string: "https://nulldull.com/proxy/")!, transport: MockTransport())
        #expect(try client.grid.assetURL("/a").absoluteString == "https://nulldull.com/a?key=\(publicKey)")
    }
}

// MARK: - 6. grid.downloadAsset

@Suite("6. grid.downloadAsset")
struct GridDownloadTests {
    @Test func sendsAuthorizationOnlyToTheAPIOrigin() async throws {
        let bytes = MockTransport.Reply.response(
            status: 200, headers: ["Content-Type": "image/png", "Content-Disposition": "inline; filename*=UTF-8''cover.png"],
            body: Data([1, 2, 3]))
        let h = try harness("private", [.fixture("grid/page.json"), bytes, bytes, bytes])
        let page = try await h.client.grid.getPage("nulldull-blog", slug: "context-that-survives-the-chat")
        let own = try await h.client.grid.downloadAsset(page.assets[0])
        _ = try await h.client.grid.downloadAsset("https://cdn.example.com/cover.png")
        _ = try await h.client.grid.downloadAsset(try #require(page.cover))
        #expect(own.contentType == "image/png")
        #expect(own.filename == "cover.png")
        #expect(own.size == 3)
        let requests = h.transport.requests
        #expect(requests[1].url?.host == "nulldull.com")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(privateKey)")
        #expect(requests[1].value(forHTTPHeaderField: "Accept") == "*/*")
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[3].value(forHTTPHeaderField: "Authorization") == "Bearer \(privateKey)")
        #expect(await failure { _ = try await h.client.grid.downloadAsset("") }.code == .invalidArgument)
    }
}

// MARK: - 7. URL normalization

@Suite("7. URL normalization")
struct NormalizationTests {
    @Test func normalizesCoversAndAssetsOnly() async throws {
        let h = try harness("public", [.fixture("grid/page-list.json"), .fixture("grid/page.json")])
        let list = try await h.client.grid.listPages("nulldull-blog")
        let page = try await h.client.grid.getPage("nulldull-blog", slug: "context-that-survives-the-chat")
        #expect(list.items[0].cover?.url.hasPrefix("https://nulldull.com/api/grid/v1/") == true)
        #expect(list.items[0].raw.at("cover.url")?.stringValue == list.items[0].cover?.url)
        #expect(list.raw.at("items.0.cover.url")?.stringValue == list.items[0].cover?.url)
        #expect(list.items[1].cover == nil)
        #expect(page.assets.allSatisfy { $0.url.hasPrefix("https://nulldull.com/") })
        #expect(page.cover?.url.hasPrefix("https://nulldull.com/") == true)
        #expect(page.document.json == Fixtures.json("grid/page.json")["document"])
        #expect(page.document.nodes.count == Fixtures.json("grid/page.json").at("document.nodes")?.arrayValue?.count)
        #expect(list.pool.key == "nulldull-blog")
        #expect(list.pool.name == "The Void")
        #expect(page.title == "Context that survives the chat.")
        #expect(page.publishedAt == 1_794_701_782_546)
    }
}

// MARK: - 8. Pagination

@Suite("8. Pagination")
struct PaginationTests {
    @Test func startsFromAfterAndStopsAtNullCursor() async throws {
        let h = try harness("private", [.fixture("memory/documents-page-2.json")])
        let items = try await collect(h.client.memory.iterateDocuments(scopeID: "s", after: "cursor-1"))
        #expect(items.count == 1)
        #expect(multimap(h.transport.requests[0]) == ["after": ["cursor-1"], "scopeId": ["s"]])
    }

    @Test func continuesThroughEmptyPagesWithACursor() async throws {
        let h = try harness(
            "public",
            [
                .json(["pool": ["key": "p", "name": "P"], "items": [], "nextCursor": "c1"]),
                .json(["pool": ["key": "p", "name": "P"], "items": [], "nextCursor": "c2"]),
                .fixture("grid/page-list-last.json"),
            ])
        let items = try await collect(h.client.grid.iteratePages("p"))
        #expect(items.count == 1)
        #expect(h.transport.requests.count == 3)
    }

    @Test func raisesInvalidResponseWhenACursorRepeats() async throws {
        let page: JSONValue = [
            "items": [["id": "a", "name": "A", "kind": "workspace", "parentId": nil]], "nextCursor": "same",
        ]
        let h = try harness("private", [.json(page), .json(page)])
        var seen = 0
        let error = await failure {
            for try await _ in h.client.memory.iterateScopes() { seen += 1 }
        }
        #expect(error.code == .invalidResponse)
        #expect(seen == 2)
        #expect(h.transport.requests.count == 2)
    }

    @Test func isLazyAndStopsEarly() async throws {
        let h = try harness("private", [.fixture("memory/tags-page-1.json")])
        let stream = h.client.memory.iterateTags()
        await Task.yield()
        #expect(h.transport.requests.isEmpty)
        for try await tag in stream {
            #expect(tag.tag == "maintained")
            break
        }
        #expect(h.transport.requests.count == 1)
    }

    @Test func singlePageMethodsKeepExtraFields() async throws {
        let h = try harness("private", [.fixture("memory/folders.json")])
        let list = try await h.client.memory.listFolders(scopeID: "s", parentID: .root)
        #expect(list.here?.folders == 1)
        #expect(list.raw == Fixtures.json("memory/folders.json"))
    }
}

// MARK: - 9. Errors

@Suite("9. Errors")
struct ErrorTests {
    @Test func fillsEveryFieldFromBodyAndHeaders() async throws {
        let h = try harness(
            "private", [.fixture("errors/locale-format-unrepresentable.json", status: 400, headers: ["CF-Ray": "abc-AMS"])])
        let error = await failure { _ = try await h.client.locale.export(scopeID: workspaceID, format: .world) }
        #expect(error.status == 400)
        #expect(error.code == .invalidInput)
        #expect(error.detail == "LOCALE_FORMAT_UNREPRESENTABLE")
        #expect(error.message == "Plural values cannot be written to this format.")
        #expect(error.localizedDescription == error.message)
        #expect(error.description == error.message)
        #expect(error.requestID == "abc-AMS")
        #expect(error.retryAfter == nil)
        #expect(error.body?["key"] == "cart.items")
        #expect(error.body?["language"] == "tr")
    }

    @Test func prefersXRequestIdAndBuildsADefaultMessage() async throws {
        let h = try harness("private", [.json(["code": "FORBIDDEN"], status: 403, headers: ["X-Request-Id": "req_1", "CF-Ray": "ray"])])
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.requestID == "req_1")
        #expect(error.message == "NullDull request failed (403 FORBIDDEN).")
    }

    @Test func nonJSONErrorBodyIsRequestFailed() async throws {
        let h = try harness("private", [.text("<html>Bad</html>", status: 500, headers: ["Content-Type": "text/html"])])
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.code == .requestFailed)
        #expect(error.status == 500)
        #expect(error.body == nil)
        #expect(error.message == "NullDull request failed (500 REQUEST_FAILED).")
    }

    @Test func invalidJSONOnSuccessIsInvalidResponse() async throws {
        let h = try harness("private", [.text("<html>")])
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.code == .invalidResponse)
        #expect(error.status == 200)
    }

    @Test func unexpectedShapeOnSuccessIsInvalidResponse() async throws {
        let h = try harness("private", [.json(["items": "nope"])])
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.code == .invalidResponse)
    }

    @Test func treatsARedirectAsAnErrorInsteadOfFollowingIt() async throws {
        let h = try harness("public", [.response(status: 302, headers: ["Location": "https://evil.example/"], body: Data())])
        let error = await failure { _ = try await h.client.grid.listPages("nulldull-blog") }
        #expect(error.status == 302)
        #expect(error.code == .requestFailed)
        #expect(h.transport.requests.count == 1)
    }
}

// MARK: - 10. Retries

@Suite("10. Retries")
struct RetryTests {
    @Test func parsesRetryAfter() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-11-20T10:00:00Z")!
        #expect(parseRetryAfter("Fri, 20 Nov 2026 10:00:05 GMT", now: now) == 5)
        #expect(parseRetryAfter("Fri, 20 Nov 2026 09:00:00 GMT", now: now) == 0)
        #expect(parseRetryAfter("7") == 7)
        #expect(parseRetryAfter(" 12 ") == 12)
        #expect(parseRetryAfter("soon") == nil)
        #expect(parseRetryAfter(nil) == nil)
    }

    @Test func retries504And429WithoutRetryAfterWithBackoff() async throws {
        let h = try harness(
            "private", [.json(["code": "X"], status: 504), .json(["code": "RATE_LIMITED"], status: 429), .fixture("memory/scopes.json")])
        _ = try await h.client.memory.listScopes()
        #expect(h.sleeper.sleeps == [500, 1000])
    }

    @Test func honoursRetryAfterOfExactly30Seconds() async throws {
        let h = try harness(
            "private", [.json(["code": "RATE_LIMITED"], status: 429, headers: ["Retry-After": "30"]), .fixture("memory/scopes.json")])
        _ = try await h.client.memory.listScopes()
        #expect(h.sleeper.sleeps == [30000])
    }

    @Test func raisesRetryAfterOver30AtOnce() async throws {
        let h = try harness("private", [.json(["code": "RATE_LIMITED"], status: 429, headers: ["Retry-After": "31"])])
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.retryAfter == 31)
        #expect(h.sleeper.sleeps.isEmpty)
        #expect(h.transport.requests.count == 1)
    }

    @Test func maxRetriesZeroDisablesRetries() async throws {
        let h = try harness("private", [.json(["code": "SERVICE_UNAVAILABLE"], status: 503)], maxRetries: 0)
        #expect(await failure { _ = try await h.client.memory.listScopes() }.code == .serviceUnavailable)
        #expect(h.transport.requests.count == 1)
    }

    @Test(arguments: [400, 401, 403, 404, 409, 500])
    func neverRetries(status: Int) async throws {
        let h = try harness("private", [.json(["code": "X"], status: status)])
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.status == status)
        #expect(h.transport.requests.count == 1)
    }

    @Test func retriesNetworkErrorsAndReportsNetworkError() async throws {
        let h = try harness(
            "private",
            [.failure(URLError(.networkConnectionLost)), .failure(URLError(.cannotFindHost)), .failure(URLError(.notConnectedToInternet))])
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.code == .networkError)
        #expect(error.status == 0)
        #expect(error.underlyingError is URLError)
        #expect(h.transport.requests.count == 3)
        #expect(h.sleeper.sleeps == [500, 1000])
    }

    @Test func recoversAfterOneNetworkError() async throws {
        let h = try harness("private", [.failure(URLError(.networkConnectionLost)), .fixture("memory/scopes.json")])
        #expect(try await h.client.memory.listScopes().items.count == 3)
    }

    @Test func doesNotRetryTimeouts() async throws {
        let h = try harness("private", [.hang, .hang], timeout: 0.05)
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.code == .timeout)
        #expect(h.transport.requests.count == 1)
    }

    @Test func doesNotRetryURLSessionTimeouts() async throws {
        let h = try harness("private", [.failure(URLError(.timedOut)), .fixture("memory/scopes.json")])
        #expect(await failure { _ = try await h.client.memory.listScopes() }.code == .timeout)
        #expect(h.transport.requests.count == 1)
    }

    @Test func retriesDownloadsToo() async throws {
        let h = try harness("private", [.json(["code": "X"], status: 502), .text("ok")])
        #expect(try await h.client.memory.downloadAsset("a").bytes == Data("ok".utf8))
        #expect(h.sleeper.sleeps == [500])
    }
}

// MARK: - 11. Timeouts and cancellation

@Suite("11. Timeouts and cancellation")
struct CancellationTests {
    @Test func raisesTimeout() async throws {
        let h = try harness("private", [.hang], timeout: 0.05)
        let error = await failure { _ = try await h.client.memory.listScopes() }
        #expect(error.code == .timeout)
        #expect(error.status == 0)
    }

    @Test func raisesAbortedWhenTheTaskIsCancelled() async throws {
        let h = try harness("private", [.hang])
        let task = Task { try await h.client.memory.listScopes() }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let error = await failure { _ = try await task.value }
        #expect(error.code == .aborted)
    }

    @Test func raisesAbortedForAnAlreadyCancelledTaskWithoutARequest() async throws {
        let h = try harness("public")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await h.client.grid.getPage("p", slug: "s")
        }
        let error = await failure { _ = try await task.value }
        #expect(error.code == .aborted)
        #expect(h.transport.requests.isEmpty)
    }

    @Test func raisesAbortedWhileWaitingToRetry() async throws {
        let transport = MockTransport([.json(["code": "SERVICE_UNAVAILABLE"], status: 503)])
        let client = try NullDullClient(apiKey: privateKey, workspaceID: workspaceID, transport: transport)
        let task = Task { try await client.memory.listScopes() }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let error = await failure { _ = try await task.value }
        #expect(error.code == .aborted)
        #expect(transport.requests.count == 1)
    }

    @Test func cancellingAnIterationRaisesAborted() async throws {
        let h = try harness("private", [.hang])
        let task = Task { try await collect(h.client.memory.iterateScopes()) }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let error = await failure { _ = try await task.value }
        #expect(error.code == .aborted)
    }
}

// MARK: - 12. Memory filters

@Suite("12. Memory filters")
struct MemoryFilterTests {
    @Test func sendsRootForRootAndNothingWhenOmitted() async throws {
        let h = try harness("private", [.json(emptyPage), .json(emptyPage), .json(emptyPage), .json(emptyPage), .json(emptyPage)])
        _ = try await h.client.memory.listAssets(folderID: .root)
        _ = try await h.client.memory.listFolders(parentID: "root")
        _ = try await h.client.memory.listDocuments()
        _ = try await h.client.memory.listDocuments(tags: [])
        _ = try await h.client.memory.listDocuments(folderID: "f1", tags: ["a", "b"], kind: .unclassified, lifecycle: .oneTime)
        let requests = h.transport.requests
        #expect(search(requests[0]) == "?folderId=root")
        #expect(search(requests[1]) == "?parentId=root")
        #expect(search(requests[2]) == "")
        #expect(search(requests[3]) == "")
        #expect(search(requests[4]) == "?folderId=f1&tag=a&tag=b&kind=unknown&lifecycle=one-time")
    }

    @Test func downloadsPreviewsWithPreviewAndWidth() async throws {
        let h = try harness("private", [.text("a"), .text("b"), .text("c")])
        _ = try await h.client.memory.downloadAsset("a1", width: 256)
        _ = try await h.client.memory.downloadAsset("a1", preview: true)
        _ = try await h.client.memory.downloadAsset("a1", revisionID: "r1")
        let requests = h.transport.requests
        #expect(search(requests[0]) == "?preview=true&w=256")
        #expect(search(requests[1]) == "?preview=true")
        #expect(search(requests[2]) == "?revisionId=r1")
        #expect(!requests.contains { multimap($0)["submissionId"] != nil })
        #expect(await failure { _ = try await h.client.memory.downloadAsset("a1", width: 0) }.code == .invalidArgument)
    }

    @Test func searchSendsQAndFilters() async throws {
        let h = try harness("private", [.fixture("memory/search.json")])
        _ = try await h.client.memory.search("a b&c", scopeID: "s", tags: ["x"], kind: .rules)
        #expect(search(h.transport.requests[0]) == "?q=a%20b%26c&scopeId=s&tag=x&kind=rules")
    }
}

// MARK: - 13. Locale export

@Suite("13. Locale export")
struct LocaleExportTests {
    @Test func alwaysSendsFormatCommaJoinsListsAndNeverSendsLanguage() async throws {
        let h = try harness("private", [.fixture("locale/export-json.json"), .fixture("locale/export-json.json"), .fixture("locale/export-json.json")])
        _ = try await h.client.locale.export(scopeID: "scope_1", languages: ["tr"])
        _ = try await h.client.locale.export(scopeID: "scope_1", languages: ["en", "pt-br"], status: [.approved, .needsReview])
        _ = try await h.client.locale.export(scopeID: "scope_1", languages: [], status: [])
        let requests = h.transport.requests
        #expect(search(requests[0]) == "?scopeId=scope_1&format=json&languages=tr")
        #expect(search(requests[1]) == "?scopeId=scope_1&format=json&languages=en%2Cpt-br&status=approved%2Cneeds_review")
        #expect(search(requests[2]) == "?scopeId=scope_1&format=json")
        #expect(!requests.contains { multimap($0)["language"] != nil })
    }

    @Test func sendsUnknownFormatsAsGiven() async throws {
        let h = try harness("private", [.fixture("locale/export-json.json")])
        _ = try await h.client.locale.export(scopeID: "s", format: "future-format")
        #expect(multimap(h.transport.requests[0])["format"] == ["future-format"])
    }

    @Test func rejectsAMissingScopeAndCommaContainingLanguages() async throws {
        let h = try harness("private")
        #expect(await failure { _ = try await h.client.locale.export(scopeID: "") }.code == .invalidArgument)
        #expect(await failure { _ = try await h.client.locale.export(scopeID: "s", languages: ["en,tr"]) }.code == .invalidArgument)
        #expect(await failure { _ = try await h.client.locale.export(scopeID: "s", languages: [""]) }.code == .invalidArgument)
        #expect(h.transport.requests.isEmpty)
    }

    @Test func writesFilesAndRejectsUnsafePaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nulldull-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = try JSONDecoder().decode(LocaleExport.self, from: Fixtures.data("locale/export-android-xml.json"))
        let written = try export.write(to: directory)
        #expect(written.count == export.files.count)
        #expect(try String(contentsOf: directory.appendingPathComponent(export.files[1].path), encoding: .utf8) == export.files[1].content)
        for path in ["/etc/passwd", "../x.json", "a/../../x.json", "a//b.json", ""] {
            let unsafe: JSONValue = ["format": "json", "files": [["path": .string(path), "contentType": "text/plain", "content": "x"]], "notes": [], "contentVersion": 1]
            let model = try unsafe.decode(LocaleExport.self)
            #expect(throws: NullDullError.self) { try model.write(to: directory) }
        }
    }
}

// MARK: - 14. Content-Disposition

@Suite("14. Content-Disposition")
struct ContentDispositionTests {
    @Test func decodesFilenameStarAndFallsBack() {
        #expect(parseFilename("attachment; filename*=UTF-8''%C3%B6deme%20plan.pdf") == "ödeme plan.pdf")
        #expect(parseFilename(#"attachment; filename="report \"q3\".csv""#) == #"report "q3".csv"#)
        #expect(parseFilename("inline; filename=logo.png") == "logo.png")
        #expect(parseFilename(#"attachment; filename="fallback.txt"; filename*=UTF-8''real.txt"#) == "real.txt")
        #expect(parseFilename("attachment; filename*=UTF-8''%E0%A4%A; filename=\"broken.txt\"") == "broken.txt")
        #expect(parseFilename("attachment") == nil)
        #expect(parseFilename(nil) == nil)
    }
}

// MARK: - Decoding tolerance

@Suite("Decoding")
struct DecodingTests {
    @Test func toleratesUnknownFieldsAndEnumValues() throws {
        let json: JSONValue = [
            "id": "s1", "name": "S", "kind": "galaxy", "parentId": nil, "iconKind": "hologram", "brandNew": ["nested": true],
        ]
        let scope = try json.decode(Scope.self)
        #expect(scope.kind == .unknown("galaxy"))
        #expect(scope.kind.rawValue == "galaxy")
        #expect(scope.iconKind == .unknown("hologram"))
        #expect(scope.raw["brandNew"]?["nested"] == true)
        #expect(try JSONValue(encoding: scope) == json)
    }

    @Test func knownEnumValuesRoundTrip() throws {
        #expect(LocationKind(rawValue: "customer-product") == .customerProduct)
        #expect(FileKind(rawValue: "unknown") == .unclassified)
        #expect(FileLifecycle(rawValue: "one-time") == .oneTime)
        #expect(LocaleFormatID(rawValue: "world-cldr") == .worldCLDR)
        #expect(LocaleKeyStatus.needsReview.rawValue == "needs_review")
        #expect(LocalePlurals(rawValue: "none") == .unsupported)
    }

    @Test func modelsEncodeTheirRawJSON() throws {
        for file in ["memory/document.json", "memory/asset.json", "memory/folder.json", "locale/formats.json"] {
            let value = Fixtures.json(file)
            switch file {
            case "memory/document.json": #expect(try JSONValue(encoding: value.decode(Document.self)) == value)
            case "memory/asset.json": #expect(try JSONValue(encoding: value.decode(Asset.self)) == value)
            case "memory/folder.json": #expect(try JSONValue(encoding: value.decode(Folder.self)) == value)
            default: #expect(try JSONValue(encoding: value.decode(LocaleFormatList.self)) == value)
            }
        }
    }

    @Test func linkResolutionShapes() throws {
        let found = try Fixtures.json("memory/resolve-link-found.json").decode(LinkResolution.self)
        #expect(found.status == .found)
        #expect(found.fragment == "before-you-ship")
        let unavailable = try Fixtures.json("memory/resolve-link-unavailable.json").decode(LinkResolution.self)
        #expect(unavailable.status == .unavailable)
        #expect(unavailable.id == nil)
    }

    @Test func gridDocumentDecodesIntoCustomModels() throws {
        struct Minimal: Decodable { let nodes: [Node]; struct Node: Decodable { let id: String; let kind: String } }
        let page = try Fixtures.json("grid/page.json").decode(GridPage.self)
        let minimal = try page.document.decode(Minimal.self)
        #expect(minimal.nodes.first?.id == "markdown-0")
        #expect(page.document.layout["columns"] == 12)
    }
}
