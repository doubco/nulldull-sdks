import Foundation
import XCTest
@testable import NullDullGrid

final class PageLinkTests: XCTestCase {
  func testSharedPublishedCorpusRoundTripsAtBothLimits() throws {
    let documents = try XCTUnwrap(Fixtures.json("page-links/published.json").array)
    XCTAssertEqual(documents.count, 17)
    for raw in documents {
      let document = try GridValidator.validate(raw)
      XCTAssertTrue(JSONValue.object(document.json).sameValue(as: raw))
    }
    let last = try GridValidator.validate(XCTUnwrap(documents.last))
    XCTAssertEqual(last.jsonString.utf8.count, 180000)
  }

  func testCurrentBindingControlsTheSameStructuredLink() throws {
    var page = try JSONDecoder().decode(PublicGridPage.self, from: Fixtures.data("../grid/page-links.json"))
    let document = page.document
    guard case .builtin(let tile) = document.nodes[1] else { return XCTFail("missing tile") }
    let link = try XCTUnwrap(tile.pageLink)
    let resolver: GridPageLinkResolver = { target, anchor in
      XCTAssertEqual(target.entryId, "guide")
      return "/\(target.pool)/\(target.locale)/\(target.slug)" + (anchor.map { "#" + $0 } ?? "")
    }
    func route() -> String? { link.resolvedURL(in: page.pageTargets, using: resolver)?.absoluteString }
    XCTAssertEqual(route(), "/manual/en/getting-started#chapter")
    XCTAssertNil(link.resolvedURL(in: page.pageTargets, using: nil))
    XCTAssertNil(link.resolvedURL(in: page.pageTargets) { _, _ in nil })
    page.pageTargets["~1"] = PublishedGridPageTarget(entryId: "guide", pool: "handbook", slug: "new-name", locale: "tr")
    XCTAssertEqual(route(), "/handbook/tr/new-name#chapter")
    page.pageTargets = [:]
    XCTAssertNil(route())
    XCTAssertEqual(page.document, document)
    let legacy = try JSONDecoder().decode(PublicGridPage.self, from: Fixtures.data("page-links/legacy.json"))
    XCTAssertTrue(legacy.pageTargets.isEmpty)
    guard case .builtin(let old) = legacy.document.nodes[1] else { return XCTFail("missing legacy tile") }
    XCTAssertNil(old.pageLink)
    XCTAssertEqual(old.link, "https://example.org/legacy")
  }

  func testAliasSyntaxAndResolverOutput() throws {
    for invalid in ["~0", "~01", "~65", "guide", "~1#", "~1#a#b", "~1#no/space", "~1#" + String(repeating: "a", count: 129)] {
      XCTAssertNil(GridPageLink(destination: "grid-page:v1:" + invalid), invalid)
    }
    let link = try XCTUnwrap(GridPageLink(destination: "grid-page:v1:~64#A-._~9"))
    let targets = ["~64": PublishedGridPageTarget(entryId: "guide", pool: "manual", slug: "guide", locale: "en")]
    struct Route: Decodable { let input: String; let href: String?; let external: Bool? }
    for route in try JSONDecoder().decode([Route].self, from: Fixtures.data("page-links/routes.json")) {
      XCTAssertEqual(link.resolvedURL(in: targets) { _, _ in route.input }?.absoluteString, route.href, route.input)
      if route.external == true {
        let opened = GridURL.safeHref(route.input).flatMap { URL(string: $0) }
        XCTAssertEqual(opened?.absoluteString, route.href, route.input)
      }
    }
  }
}
