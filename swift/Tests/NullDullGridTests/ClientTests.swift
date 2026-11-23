import Foundation
import XCTest

@testable import NullDullGrid

/// Serves canned responses and records requests. One handler per test (tests run serially in this class).
final class StubProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
  nonisolated(unsafe) static var requests: [URLRequest] = []
  nonisolated(unsafe) static var delay: TimeInterval = 0

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    StubProtocol.requests.append(request)
    let respond = { [self] in
      do {
        let (status, headers, body) = try StubProtocol.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        if (300..<400).contains(status), let location = headers["Location"], let target = URL(string: location) {
          client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
      } catch {
        client?.urlProtocol(self, didFailWithError: error)
      }
    }
    if StubProtocol.delay > 0 {
      DispatchQueue.global().asyncAfter(deadline: .now() + StubProtocol.delay, execute: respond)
    } else {
      respond()
    }
  }
  override func stopLoading() {}
}

final class ClientTests: XCTestCase {
  static let publicKey = "nd_pub_" + String(repeating: "a1", count: 32)
  static let privateKey = "nd_sec_" + String(repeating: "b2", count: 32)

  var session: URLSession!

  override func setUp() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    session = URLSession(configuration: configuration)
    StubProtocol.requests = []
    StubProtocol.delay = 0
  }

  func client(apiKey: String? = publicKey) throws -> GridPublicClient {
    try GridPublicClient(baseURL: URL(string: "https://example.com/api/grid/v1")!, apiKey: apiKey, session: session)
  }

  func testGetPageSendsBearerKeyValidatesDocumentAndResolvesAssets() async throws {
    let body = try Fixtures.data("delivery/page.json")
    StubProtocol.handler = { _ in (200, ["Content-Type": "application/json"], body) }
    let page = try await client().page(pool: "example-pool", slug: "showcase")
    let request = try XCTUnwrap(StubProtocol.requests.first)
    XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/grid/v1/pools/example-pool/pages/showcase?locale=en")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.publicKey)")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    XCTAssertFalse(request.httpShouldHandleCookies)
    XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    XCTAssertEqual(page.summary.folderId, "folder-a")
    XCTAssertEqual(page.document, try Fixtures.document("showcase-fixed"))
    XCTAssertEqual(
      page.assets.first?.url,
      "https://example.com/api/grid/v1/pools/example-pool/pages/showcase/assets/photo?version=1&key=\(Self.publicKey)")
    XCTAssertEqual(page.cover?.url, page.assets.first?.url)
    XCTAssertEqual(page.cover?.alt, "A coastline at dusk")
  }

  func testLegacySnapshotWithoutCoverOrFolder() async throws {
    let body = try Fixtures.data("delivery/page-legacy.json")
    StubProtocol.handler = { _ in (200, [:], body) }
    let page = try await client(apiKey: nil).page(pool: "example-pool", slug: "welcome-to-the-void")
    XCTAssertNil(page.cover)
    XCTAssertNil(page.summary.folderId)
    XCTAssertTrue(page.document.layout.isFlow)
    XCTAssertNil(StubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"))
  }

  func testListPagesEncodesQueryLikeURLSearchParams() async throws {
    let body = try Fixtures.data("delivery/list.json")
    StubProtocol.handler = { _ in (200, [:], body) }
    let list = try await client().pages(
      pool: "example-pool", locale: "pt-br", query: "space & word", folderId: "folder_a", limit: 2, after: "a+b==")
    XCTAssertEqual(
      StubProtocol.requests.first?.url?.absoluteString,
      "https://example.com/api/grid/v1/pools/example-pool/pages?locale=pt-br&after=a%2Bb%3D%3D&q=space+%26+word&folderId=folder_a&limit=2")
    XCTAssertEqual(list.items.count, 3)
    XCTAssertEqual(list.nextCursor, "opaque-cursor+/=")
    XCTAssertEqual(list.items[0].cover?.url.hasSuffix("key=\(Self.publicKey)"), true)
    XCTAssertNil(list.items[1].cover)
    XCTAssertNil(list.items[2].folderId)
  }

  func testArgumentsAreValidatedBeforeAnyRequest() async throws {
    StubProtocol.handler = { _ in XCTFail("no request expected"); return (500, [:], Data()) }
    let client = try client()
    await assertThrows(try await client.page(pool: "../private", slug: "x"))
    await assertThrows(try await client.page(pool: "ok", slug: "x", locale: "EN"))
    await assertThrows(try await client.pages(pool: "ok", folderId: "../private"))
    XCTAssertTrue(StubProtocol.requests.isEmpty)
  }

  func testHTTPErrorsCarryStatusAndCode() async throws {
    StubProtocol.handler = { _ in (404, [:], Data(#"{"code":"NOT_FOUND"}"#.utf8)) }
    do {
      _ = try await client().page(pool: "demo", slug: "missing")
      XCTFail("expected error")
    } catch let error as GridPublicError {
      XCTAssertEqual(error, GridPublicError(status: 404, code: "NOT_FOUND"))
    }
    StubProtocol.handler = { _ in (502, [:], Data("<html>".utf8)) }
    do {
      _ = try await client().page(pool: "demo", slug: "missing")
      XCTFail("expected error")
    } catch let error as GridPublicError {
      XCTAssertEqual(error, GridPublicError(status: 502, code: "REQUEST_FAILED"))
    }
  }

  func testPausedPublicRequestsCarryReasonRenewalAndRetryAfter() async throws {
    let body = Data(
      #"{"code":"RATE_LIMITED","reason":"PUBLIC_REQUESTS_PAUSED","detail":"PUBLIC_REQUESTS_PAUSED","message":"This workspace has used its monthly public requests. Public delivery resumes when the allowance renews.","period":"2026-11","renewsAt":"2026-12-01T00:00:00.000Z"}"#
        .utf8)
    StubProtocol.handler = { _ in (429, ["Content-Type": "application/json", "Retry-After": "691200"], body) }
    do {
      _ = try await client().pages(pool: "demo")
      XCTFail("expected error")
    } catch let error as GridPublicError {
      XCTAssertEqual(error, GridPublicError(status: 429, code: "RATE_LIMITED"))
      XCTAssertTrue(error.isPublicRequestsPaused)
      XCTAssertEqual(error.reason, GridPublicError.publicRequestsPausedReason)
      XCTAssertEqual(error.detail, "PUBLIC_REQUESTS_PAUSED")
      XCTAssertEqual(error.renewsAt, "2026-12-01T00:00:00.000Z")
      XCTAssertEqual(error.retryAfter, 691200)
    }
    XCTAssertEqual(StubProtocol.requests.count, 1)

    StubProtocol.handler = { _ in (429, ["Retry-After": "60"], Data(#"{"code":"RATE_LIMITED"}"#.utf8)) }
    do {
      _ = try await client().pages(pool: "demo")
      XCTFail("expected error")
    } catch let error as GridPublicError {
      XCTAssertFalse(error.isPublicRequestsPaused)
      XCTAssertNil(error.reason)
      XCTAssertNil(error.renewsAt)
      XCTAssertEqual(error.retryAfter, 60)
    }
  }

  func testRetryAfterParsesSecondsAndHTTPDates() {
    let now = Date(timeIntervalSince1970: 1_795_168_800)  // Fri, 20 Nov 2026 10:00:00 GMT
    XCTAssertEqual(GridPublicError.parseRetryAfter("7"), 7)
    XCTAssertEqual(GridPublicError.parseRetryAfter("Fri, 20 Nov 2026 10:00:05 GMT", now: now), 5)
    XCTAssertEqual(GridPublicError.parseRetryAfter("Fri, 20 Nov 2026 09:00:00 GMT", now: now), 0)
    XCTAssertNil(GridPublicError.parseRetryAfter("soon"))
    XCTAssertNil(GridPublicError.parseRetryAfter(nil))
  }

  func testRedirectsAreNotFollowed() async throws {
    StubProtocol.handler = { request in
      if request.url?.host == "elsewhere.example" { XCTFail("redirect followed") }
      return (302, ["Location": "https://elsewhere.example/steal"], Data())
    }
    do {
      _ = try await client().page(pool: "demo", slug: "page")
      XCTFail("expected error")
    } catch GridClientError.redirectRejected(let status) {
      XCTAssertEqual(status, 302)
    }
  }

  func testInvalidDocumentsAreRejected() async throws {
    var page = try Fixtures.json("delivery/page.json").object!
    var document = page["document"]!.object!
    var layout = document["layout"]!.object!
    layout["direction"] = .string("diagonal")
    document["layout"] = .object(layout)
    page["document"] = .object(document)
    let body = Data(JSONValue.object(page).javaScriptJSON.utf8)
    StubProtocol.handler = { _ in (200, [:], body) }
    do {
      _ = try await client().page(pool: "demo", slug: "page")
      XCTFail("expected error")
    } catch GridClientError.invalidContent(let message) {
      XCTAssertEqual(message, "Invalid option.")
    }
  }

  func testKeysAreCheckedAndPrivateKeysStayOutOfURLs() async throws {
    XCTAssertThrowsError(try client(apiKey: "nd_pub_short"))
    XCTAssertThrowsError(try client(apiKey: "sk_live_" + String(repeating: "a", count: 64)))
    XCTAssertThrowsError(try GridPublicClient(baseURL: URL(string: "ftp://example.com")!))
    XCTAssertThrowsError(try GridPublicClient(baseURL: URL(string: "https://user:pw@example.com/api")!))
    XCTAssertThrowsError(try GridPublicClient(baseURL: URL(string: "https://example.com/api?x=1")!))
    #if os(macOS)
      // Server/tooling use on macOS: sent as a header, never added to asset URLs.
      let server = try client(apiKey: Self.privateKey)
      XCTAssertEqual(server.assetURL("/a?version=1")?.absoluteString, "https://example.com/a?version=1")
    #else
      XCTAssertThrowsError(try client(apiKey: Self.privateKey))
    #endif
    let publicClient = try client()
    XCTAssertEqual(publicClient.assetURL("/a?key=existing")?.absoluteString, "https://example.com/a?key=existing")
  }

  func testPublicKeysAreOnlyAddedToAssetsOnTheAPIOrigin() throws {
    let publicClient = try client()
    XCTAssertEqual(publicClient.assetURL("/a.png")?.absoluteString, "https://example.com/a.png?key=\(Self.publicKey)")
    XCTAssertEqual(
      publicClient.assetURL("https://EXAMPLE.com:443/a.png")?.absoluteString,
      "https://EXAMPLE.com:443/a.png?key=\(Self.publicKey)")
    // Foreign hosts, other schemes and other ports never receive the key.
    XCTAssertEqual(publicClient.assetURL("https://cdn.example/a.png")?.absoluteString, "https://cdn.example/a.png")
    XCTAssertEqual(publicClient.assetURL("//cdn.example/a.png")?.absoluteString, "https://cdn.example/a.png")
    XCTAssertEqual(publicClient.assetURL("http://example.com/a.png")?.absoluteString, "http://example.com/a.png")
    XCTAssertEqual(publicClient.assetURL("https://example.com:8443/a.png")?.absoluteString, "https://example.com:8443/a.png")
    XCTAssertEqual(publicClient.assetURL("https://example.com.evil/a.png")?.absoluteString, "https://example.com.evil/a.png")
  }

  func testCancellationStopsTheRequest() async throws {
    StubProtocol.delay = 2
    StubProtocol.handler = { _ in (200, [:], try Fixtures.data("delivery/page.json")) }
    let client = try client()
    let task = Task { try await client.page(pool: "demo", slug: "page") }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError, "\(error)")
    }
  }

  private func assertThrows<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do {
      _ = try await expression()
      XCTFail("expected an error", file: file, line: line)
    } catch {}
  }
}
