import Foundation
import XCTest

@testable import NullDullGrid

final class ValidationTests: XCTestCase {
  /// Every case grid-core accepts is accepted and normalized identically; every rejection has the same message.
  func testSharedValidationCases() throws {
    let cases = try XCTUnwrap(Fixtures.json("validation/cases.json").array)
    XCTAssertGreaterThan(cases.count, 100)
    for entry in cases {
      let name = entry["name"]?.string ?? "?"
      let input: JSONValue
      if let text = entry["inputJSON"]?.string {
        input = try JSONValue.parse(text)
      } else {
        input = try XCTUnwrap(entry["input"], name)
      }
      do {
        let document = try GridValidator.validate(input)
        XCTAssertEqual(entry["valid"]?.bool, true, "\(name) should be rejected with \(entry["error"]?.string ?? "")")
        if let output = entry["output"] {
          XCTAssertTrue(JSONValue.object(document.json).sameValue(as: output), "\(name) normalizes differently")
          // Key order matters for the 180 KB limit's byte count.
          XCTAssertEqual(document.jsonString, output.javaScriptJSON, "\(name) serializes differently")
        }
      } catch let error as GridValidationError {
        XCTAssertEqual(entry["valid"]?.bool, false, "\(name) should be valid, got \(error.message)")
        XCTAssertEqual(error.message, entry["error"]?.string, name)
      }
    }
  }

  func testRealDocumentsRoundTripThroughCodable() throws {
    let names = Fixtures.documentNames
    XCTAssertTrue(names.contains("void-welcome-to-the-void"))
    XCTAssertEqual(names.filter { $0.hasPrefix("void-") }.count, 16)
    for name in names {
      let raw = try Fixtures.json("documents/\(name).json")
      let document = try JSONDecoder().decode(GridDocument.self, from: Fixtures.data("documents/\(name).json"))
      XCTAssertTrue(JSONValue.object(document.json).sameValue(as: raw), name)
      let encoded = try JSONEncoder().encode(document)
      XCTAssertEqual(try JSONDecoder().decode(GridDocument.self, from: encoded), document, name)
    }
  }

  func testJSONParserKeepsJavaScriptDistinctions() throws {
    let value = try JSONValue.parse(#"{"b":1,"a":true,"c":null,"d":"😀","e":2.5e1}"#)
    XCTAssertEqual(value.object?.keys, ["b", "a", "c", "d", "e"])
    XCTAssertEqual(value["a"], .bool(true))
    XCTAssertEqual(value["b"], .number(1))
    XCTAssertEqual(value["c"], .null)
    XCTAssertNil(value["missing"])
    XCTAssertEqual(value["d"]?.string, "😀")
    XCTAssertEqual(value.javaScriptJSON, #"{"b":1,"a":true,"c":null,"d":"😀","e":25}"#)
    XCTAssertThrowsError(try JSONValue.parse("{\"a\":1,}"))
    XCTAssertEqual(JSONValue.javaScriptNumber(0.1), "0.1")
    XCTAssertEqual(JSONValue.javaScriptNumber(1e-7), "1e-7")
    XCTAssertEqual(JSONValue.javaScriptNumber(-45.5), "-45.5")
  }

  func testSafeURLsMatchWHATWGSerialization() {
    XCTAssertEqual(GridURL.safeHref("HTTPS://Example.COM:443/a/./b/../c?q=a b#frag"), "https://example.com/a/c?q=a%20b#frag")
    XCTAssertEqual(GridURL.safeHref("http://example.com:80"), "http://example.com/")
    XCTAssertEqual(GridURL.safeHref("https:example.com"), "https://example.com/")
    XCTAssertEqual(GridURL.safeHref("https://example.com/caf\u{e9}"), "https://example.com/caf%C3%A9")
    XCTAssertEqual(GridURL.safeHref(" https://@example.com/ "), "https://example.com/")
    XCTAssertNil(GridURL.safeHref("javascript:alert(1)"))
    XCTAssertNil(GridURL.safeHref("https://user:pw@example.com"))
    XCTAssertNil(GridURL.safeHref("/relative"))
    XCTAssertNil(GridURL.safeHref("https://exa mple.com"))
    XCTAssertNil(GridURL.safeHref("https://example.com:99999"))
    XCTAssertNil(GridURL.safeHref(nil))
  }

  /// `validation/urls.json`: `safeGridUrl` and `gridEmbedUrl` results from the React package.
  func testSharedURLTableMatchesTheWebRenderer() throws {
    let cases = try XCTUnwrap(Fixtures.json("validation/urls.json").array)
    XCTAssertGreaterThan(cases.count, 0)
    for entry in cases {
      let input = try XCTUnwrap(entry["input"]?.string)
      if input.contains("bücher") {
        // Known difference (README parity table): internationalized host names stay in Unicode
        // instead of being converted to Punycode as `URL.href` does. The URL is still accepted.
        XCTAssertNotNil(GridURL.safeHref(input), input)
        XCTAssertNotNil(entry["safe"]?.string, input)
        continue
      }
      XCTAssertEqual(GridURL.safeHref(input), entry["safe"]?.string, "safe(\(input))")
      XCTAssertEqual(GridEmbed(input)?.playerURL, entry["embed"]?.string, "embed(\(input))")
    }
  }

  func testRestrictedEmbedsMatchTheWebRenderer() {
    XCTAssertEqual(GridEmbed("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.playerURL, "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ")
    XCTAssertEqual(GridEmbed("https://youtu.be/dQw4w9WgXcQ")?.playerURL, "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ")
    XCTAssertEqual(GridEmbed("https://youtube.com/shorts/dQw4w9WgXcQ")?.provider, .youtube)
    XCTAssertEqual(GridEmbed("https://vimeo.com/76979871")?.playerURL, "https://player.vimeo.com/video/76979871")
    XCTAssertNil(GridEmbed("https://www.youtube.com/watch?v=short"))
    XCTAssertNil(GridEmbed("https://evil.example/watch?v=dQw4w9WgXcQ"))
    XCTAssertNil(GridEmbed("javascript:alert(1)"))
  }

  func testPublicArguments() {
    XCTAssertTrue(GridPublicArguments.isPublicKey("nulldull-blog"))
    XCTAssertFalse(GridPublicArguments.isPublicKey("../private"))
    XCTAssertFalse(GridPublicArguments.isPublicKey("double--hyphen"))
    XCTAssertFalse(GridPublicArguments.isPublicKey("Upper"))
    XCTAssertTrue(GridPublicArguments.isLocale("pt-br"))
    XCTAssertFalse(GridPublicArguments.isLocale("EN"))
    XCTAssertFalse(GridPublicArguments.isLocale("e"))
  }
}
