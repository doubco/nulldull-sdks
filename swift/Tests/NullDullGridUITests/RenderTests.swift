import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import NullDullGrid
@testable import NullDullGridUI

/// Renders fixture documents with `ImageRenderer`.
///
/// Set `GRID_RENDER_OUTPUT=/some/dir` (and optionally `GRID_RENDER_ASSETS` with photo.png,
/// tile.png, logo.svg and font.ttf) to also write PNGs for side-by-side review with the web renderer.
@available(iOS 16, macOS 13, tvOS 16, *)
@MainActor
final class RenderTests: XCTestCase {
  /// `<repo>/fixtures/grid-renderer`, shared with NullDullGridTests and the Kotlin renderer.
  static let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // NullDullGridUITests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // swift
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("fixtures/grid-renderer")

  func document(_ name: String) throws -> GridDocument {
    try GridDocument(json: Data(contentsOf: Self.fixtures.appendingPathComponent("documents/\(name).json")))
  }

  static func assetURL(_ id: String) -> URL? { URL(string: "https://assets.example/\(id)") }

  /// A store preloaded with generated (or supplied) assets so rendering is synchronous.
  func store() throws -> GridAssetStore {
    let store = GridAssetStore()
    let directory = ProcessInfo.processInfo.environment["GRID_RENDER_ASSETS"].map(URL.init(fileURLWithPath:))
    func file(_ name: String) -> Data? { directory.flatMap { try? Data(contentsOf: $0.appendingPathComponent(name)) } }
    store.preload(file("photo.png") ?? Self.png(width: 60, height: 40), for: Self.assetURL("photo")!, as: .image)
    store.preload(file("tile.png") ?? Self.png(width: 8, height: 8), for: Self.assetURL("tile")!, as: .image)
    store.preload(
      file("logo.svg") ?? Data(##"<svg viewBox="0 0 2 1"><rect width="2" height="1" rx="0.2" fill="#1f1d1a"/></svg>"##.utf8),
      for: Self.assetURL("logo")!, as: .svg)
    if let font = file("font.ttf") { store.preload(font, for: Self.assetURL("font")!, as: .font) }
    return store
  }

  static func png(width: Int, height: Int) -> Data {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.25, green: 0.35, blue: 0.62, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  var registry: GridCustomNodeRegistry {
    GridCustomNodeRegistry().register("callout") { node in
      Text(node[property: "title"] ?? "")
        .font(.system(size: 13, weight: .semibold))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(.sRGB, red: 0.91, green: 0.64, blue: 0.24, opacity: 0.25))
    }
  }

  func render(_ document: GridDocument, width: CGFloat, store: GridAssetStore, scheme: ColorScheme = .light) -> CGImage? {
    let view = GridView(
      document: document, resolveAsset: Self.assetURL, width: width, customNodes: registry)
      .gridAssetStore(store)
      .background(scheme == .dark ? Color.black : Color.white)
      .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return renderer.cgImage
  }

  func testFixedCanvasesRenderAtEngineSize() throws {
    let store = try store()
    for name in [
      "showcase-fixed", "breakpoints-padding", "react-all-kinds", "react-separators-fixed", "starter-gallery",
      "kitchen-sink", "all-shapes",
    ] {
      let document = try document(name)
      for width in [390.0, 820.0] {
        let image = try XCTUnwrap(render(document, width: width, store: store), name)
        let geometry = GridGeometry.layout(document, width: width) { _, _ in 0 }
        XCTAssertEqual(Double(image.width), width * 2, accuracy: 1, "\(name)@\(width)")
        XCTAssertEqual(Double(image.height), max(geometry.canvasHeight, 0) * 2, accuracy: 2, "\(name)@\(width)")
      }
    }
  }

  func testFlowingTextIsMeasuredFromRenderedViews() throws {
    let document = try document("void-welcome-to-the-void")
    let narrow = try XCTUnwrap(render(document, width: 320, store: store()))
    let wide = try XCTUnwrap(render(document, width: 820, store: store()))
    // Narrow columns wrap more lines, so the page is taller.
    XCTAssertGreaterThan(narrow.height, wide.height)
    XCTAssertGreaterThan(narrow.height, 320 * 2)
  }

  func testPaddedFlowRendersAtLeastItsEngineHeight() throws {
    let document = try document("flow-padded")
    for width in [320.0, 820.0] {
      let image = try XCTUnwrap(render(document, width: width, store: store()))
      let geometry = GridGeometry.layout(document, width: width) { _, _ in 0 }
      XCTAssertEqual(Double(image.width), width * 2, accuracy: 1, "flow-padded@\(width)")
      // Flowing text adds measured height on top of the engine's zero-height text boxes.
      XCTAssertGreaterThanOrEqual(Double(image.height), geometry.canvasHeight * 2 - 2, "flow-padded@\(width)")
    }
  }

  func testMarkdownStructureMatchesTheWebRenderer() {
    let blocks = GridMarkdown.parse(
      "# Head\n\nline one\nline two  \nhard <b>html</b> ~~old~~ [x](javascript:alert(1)) [y](https://example.com)\n\n- a\n  - b\n- [x] done\n\n1. one\n\n| A | B |\n|:-:|--:|\n| 1 | 2 |\n\n> q\n\n```\ncode\n```\n\n---\n\n![alt](https://example.com/i.png)\n\n<script>alert(1)</script>")
    guard case .heading(1, let heading) = blocks[0] else { return XCTFail("\(blocks[0])") }
    XCTAssertEqual(heading.map(\.text).joined(), "Head")
    guard case .paragraph(let inlines) = blocks[1] else { return XCTFail("\(blocks[1])") }
    let text = inlines.map(\.text).joined()
    XCTAssertTrue(text.hasPrefix("line one\nline two\nhard <b>html</b> old x y"), text)
    XCTAssertTrue(inlines.contains { $0.strike && $0.text == "old" })
    XCTAssertNil(inlines.first { $0.text == "x" }?.link, "unsafe link becomes text")
    XCTAssertEqual(inlines.first { $0.text == "y" }?.link?.absoluteString, "https://example.com/", "normalized like URL.href")
    guard case .list(false, let items, 0) = blocks[2] else { return XCTFail("\(blocks[2])") }
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[1].checked, true)
    guard case .list(false, _, 1) = items[0].blocks[1] else { return XCTFail("nested list") }
    guard case .list(true, _, 0) = blocks[3] else { return XCTFail("\(blocks[3])") }
    guard case .table(let alignments, let header, let rows) = blocks[4] else { return XCTFail("\(blocks[4])") }
    XCTAssertEqual(alignments, [.center, .right])
    XCTAssertEqual(header.count, 2)
    XCTAssertEqual(rows.count, 1)
    guard case .quote = blocks[5], case .code("code") = blocks[6], case .rule = blocks[7] else { return XCTFail("\(blocks)") }
    guard case .paragraph(let image) = blocks[8] else { return XCTFail("\(blocks[8])") }
    XCTAssertEqual(image.map(\.text).joined(), "alt", "images show alt text and are never fetched")
    guard case .raw(let raw) = blocks[9] else { return XCTFail("\(blocks[9])") }
    XCTAssertEqual(raw, "<script>alert(1)</script>", "HTML stays literal text")
  }

  func testPublishedPageResolvesOnlyParsedMarkdownLinks() throws {
    let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("../grid/page-links.json"))
    let page = try JSONDecoder().decode(PublicGridPage.self, from: data)
    var renderedAnchors = Set<String>()
    let view = PublishedGridPageView(page: page, resolvePageLink: { target, anchor in
      renderedAnchors.insert(anchor ?? "")
      return "/" + target.slug + (anchor.map { "#" + $0 } ?? "")
    }, width: 390)
    XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    XCTAssertEqual(renderedAnchors, ["intro", "list", "chapter", ""])
    guard case .builtin(let node) = page.document.nodes[0] else { return XCTFail("missing text") }
    let resolve = { (link: GridPageLink) in link.resolvedURL(in: view.content.pageTargets, using: view.content.resolvePageLink) }
    let blocks = GridMarkdown.parse(node.text, pageURL: resolve)
    guard case .paragraph(let first) = blocks[0], case .list(_, let items, _) = blocks[1],
      case .paragraph(let list) = items[0].blocks[0], case .table(_, _, let rows) = blocks[2] else {
      return XCTFail("missing formatted blocks")
    }
    XCTAssertEqual(first.first?.link?.absoluteString, "/getting-started#intro")
    XCTAssertNil(first.first(where: { $0.text.contains("Missing") })?.link)
    XCTAssertEqual(list.first?.link?.absoluteString, "/getting-started#list")
    XCTAssertEqual(rows[0][0].first?.link?.absoluteString, "/getting-started")
    guard case .paragraph(let inert) = GridMarkdown.parse(node.text)[0] else { return XCTFail() }
    XCTAssertTrue(inert.allSatisfy { $0.link == nil })
    for useResolver in [false, true] {
      let parsed = GridMarkdown.parse(node.text, pageURL: useResolver ? resolve : nil)
      guard case .paragraph(let angles) = parsed.last else { return XCTFail("missing autolinks") }
      XCTAssertEqual(angles.map(\.text).joined(), "grid-page:v1:~1 and grid-page:v1:~2")
      XCTAssertEqual(angles.compactMap { $0.link?.absoluteString }, useResolver ? ["/getting-started"] : [])
    }
    let refs = "[Full][ref], [ref][] and [ref].\n\n[ref]: <grid-page:v1:~1#intro>\n[ref]: grid-page:v1:~2"
    guard case .paragraph(let references) = GridMarkdown.parse(refs, pageURL: resolve)[0] else { return XCTFail() }
    XCTAssertEqual(references.filter { $0.link != nil }.map(\.text), ["Full", "ref", "ref"])
    let source = "<grid-page:v1:~1> and `[code](grid-page:v1:~1)` and [web](https://example.org)"
    guard case .paragraph(let runs) = GridMarkdown.parse(source, pageURL: resolve)[0] else { return XCTFail() }
    XCTAssertEqual(runs.compactMap { $0.link?.absoluteString }, ["/getting-started", "https://example.org/"])
  }

  func testAnchoredPageLinksPreserveLabelsCodeAndExternalFragments() throws {
    let token = "grid-page:v1:~64#part_2"
    let outside = "https://example.com/path#grid-page:v1:~64#part_2"
    let externalHref = try XCTUnwrap(try AttributedString(markdown: "[Web](\(outside))").runs.first?.link?.absoluteString)
    let source = "**Styled** [Open](\(token)), <\(token)>, `[literal](\(token))`, [Web](\(outside)), [Read][r].\n\n[r]: <grid-page:v1:~1#list>"
    var resolved: [GridPageLink] = []
    guard case .paragraph(let runs) = GridMarkdown.parse(source, pageURL: { link in
      resolved.append(link)
      return URL(string: "/guide#" + (link.anchor ?? ""))
    }, protectPageFragments: true).first else { return XCTFail("missing paragraph") }
    let inline = try XCTUnwrap(GridPageLink(entryId: "~64", anchor: "part_2"))
    let reference = try XCTUnwrap(GridPageLink(entryId: "~1", anchor: "list"))
    XCTAssertEqual(resolved, [inline, inline, reference])
    XCTAssertEqual(runs.compactMap { $0.link?.absoluteString }, ["/guide#part_2", "/guide#part_2", externalHref, "/guide#list"])
    XCTAssertEqual(runs.map(\.text).joined(), "Styled Open, \(token), [literal](\(token)), Web, Read.")
    XCTAssertTrue(runs.contains { $0.bold && $0.text == "Styled" })
    XCTAssertTrue(runs.contains { $0.code && $0.link == nil && $0.text == "[literal](\(token))" })
    guard case .paragraph(let inert) = GridMarkdown.parse(source).first else { return XCTFail("missing paragraph") }
    XCTAssertEqual(inert.compactMap { $0.link?.absoluteString }, [externalHref])
  }

  func testCustomNodesOnlyRunRegisteredComponents() {
    let registry = GridCustomNodeRegistry().register("callout") { _ in Text("trusted") }
    XCTAssertNotNil(registry.renderer(for: "callout"))
    XCTAssertNil(registry.renderer(for: "constructor"))
    XCTAssertNil(registry.renderer(for: "Callout"))
  }

  func testWritesReviewImagesWhenRequested() throws {
    guard let output = ProcessInfo.processInfo.environment["GRID_RENDER_OUTPUT"] else {
      throw XCTSkip("Set GRID_RENDER_OUTPUT to write review images.")
    }
    let directory = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = try store()
    for name in [
      "showcase-fixed", "showcase-flow", "flow-mixed", "void-welcome-to-the-void", "react-all-kinds", "markdown-rich",
      "kitchen-sink", "flow-padded", "all-shapes",
    ] {
      for width in [390.0, 820.0] {
        let image = try XCTUnwrap(render(document(name), width: width, store: store))
        try write(image, to: directory.appendingPathComponent("\(name)-\(Int(width)).png"))
      }
    }
    let dark = try XCTUnwrap(render(document("markdown-rich"), width: 390, store: store, scheme: .dark))
    try write(dark, to: directory.appendingPathComponent("markdown-rich-390-dark.png"))
  }

  func write(_ image: CGImage, to url: URL) throws {
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }
}
