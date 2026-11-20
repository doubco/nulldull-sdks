import Foundation
import XCTest

@testable import NullDullGrid

final class SVGTests: XCTestCase {
  /// `validation/svg.json`: `isSafeGridSvg` results from grid-core.
  func testSharedSVGTableMatchesGridCore() throws {
    let cases = try XCTUnwrap(Fixtures.json("validation/svg.json").array)
    XCTAssertGreaterThan(cases.count, 0)
    for entry in cases {
      let source = try XCTUnwrap(entry["source"]?.string)
      XCTAssertEqual(GridSVG.isSafe(source), entry["safe"]?.bool, source)
    }
  }

  func testAllowlistMatchesGridCore() {
    let safe = [
      ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0h10v10z" fill="#123456"/></svg>"##,
      ##"<?xml version="1.0" encoding="UTF-8"?><!-- Figma --><svg viewBox="0 0 2 2" overflow="hidden"><g style="fill:rgb(1, 2, 3);opacity:.5 !important"><circle cx="1" cy="1" r="1"/></g></svg>"##,
      ##"<svg><defs><linearGradient id="g"><stop offset="0" stop-color="red"/></linearGradient></defs><rect width="1" height="1" fill="url(#g)"/></svg>"##,
    ]
    let unsafe = [
      ##"<svg><script>alert(1)</script></svg>"##,
      ##"<svg onload="alert(1)"></svg>"##,
      ##"<svg><image href="https://example.com/x.png"/></svg>"##,
      ##"<svg><rect fill="url(https://example.com/x)"/></svg>"##,
      ##"<svg><rect style="fill:red;behavior:url(x)"/></svg>"##,
      ##"<!DOCTYPE svg><svg></svg>"##,
      ##"<svg>&amp;</svg>"##,
      ##"<svg></svg><svg></svg>"##,
      ##"<svg><g></svg>"##,
      ##"<svg><!-- unterminated </svg>"##,
      ##"<svg xmlns="http://evil.example/"></svg>"##,
      ##"<svg><style>*{}</style></svg>"##,
      "text<svg></svg>",
    ]
    for source in safe { XCTAssertTrue(GridSVG.isSafe(source), source) }
    for source in unsafe { XCTAssertFalse(GridSVG.isSafe(source), source) }
  }

  func testDrawingResolvesShapesTransformsAndPaint() throws {
    let drawing = try GridSVG.drawing(
      ##"<svg width="20" height="10" viewBox="0 0 40 20"><g transform="translate(5 0) scale(2)" fill="#ff0000" opacity="0.5"><rect x="1" y="1" width="4" height="2" rx="1"/><circle cx="10" cy="5" r="2" stroke="black" stroke-width="2" fill="none"/></g><path d="M0 0 A5 5 0 0 1 10 10 Q 15 15 20 10 T 30 10 z"/><polygon points="0,0 4,0 2,3"/></svg>"##)
    XCTAssertEqual(drawing.intrinsicWidth, 20)
    XCTAssertEqual(drawing.intrinsicHeight, 10)
    XCTAssertEqual(drawing.viewBox.width, 40)
    XCTAssertEqual(drawing.shapes.count, 4)
    XCTAssertEqual(drawing.shapes[0].fill, .color(GridRGBA(red: 1, green: 0, blue: 0, alpha: 0.5)))
    XCTAssertEqual(drawing.shapes[0].transform, GridAffineTransform(a: 2, d: 2, tx: 5))
    XCTAssertNil(drawing.shapes[1].fill)
    XCTAssertEqual(drawing.shapes[1].stroke, .color(GridRGBA(red: 0, green: 0, blue: 0, alpha: 0.5)))
    XCTAssertEqual(drawing.shapes[2].fill, .color(GridRGBA(red: 0, green: 0, blue: 0, alpha: 1)))
    XCTAssertEqual(drawing.shapes[3].commands.last, .close)
  }

  func testUnsupportedFeaturesFailInsteadOfGuessing() {
    XCTAssertThrowsError(try GridSVG.drawing(##"<svg><defs><linearGradient id="g"/></defs><rect width="1" height="1" fill="url(#g)"/></svg>"##)) {
      XCTAssertEqual($0 as? GridSVGRenderError, .unsupported("paint server url(#g)"))
    }
    XCTAssertThrowsError(try GridSVG.drawing(##"<svg><rect width="50%" height="1"/></svg>"##))
    XCTAssertThrowsError(try GridSVG.drawing(##"<svg><script/></svg>"##)) {
      XCTAssertEqual($0 as? GridSVGRenderError, .unsafe)
    }
  }

  func testCompactPathSyntax() throws {
    let commands = try GridSVG.pathCommands("M10-5l.5.5h1v-1a1 1 0 011 1zm1,1 2,2")
    XCTAssertEqual(commands.first, .move(10, -5))
    XCTAssertEqual(commands[1], .line(10.5, -4.5))
    XCTAssertEqual(commands[2], .line(11.5, -4.5))
    XCTAssertEqual(commands.filter { if case .close = $0 { return true }; return false }.count, 1)
    XCTAssertEqual(commands.suffix(2), [.move(11, -4), .line(13, -2)], "z returns to the subpath start")
  }
}
