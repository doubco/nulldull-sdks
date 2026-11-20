import Foundation
import XCTest

@testable import NullDullGrid

/// Compares the Swift layout engine with golden geometry produced by the TypeScript
/// reference (`fixtures/grid-renderer`), itself checked against `@nulldull/grid-react`.
final class GoldenGeometryTests: XCTestCase {
  func testLayoutMatchesTypeScriptGoldens() throws {
    let golden = try Fixtures.json("golden/layout.json")
    XCTAssertEqual(golden["measure"]?.string, "stubTextHeight")
    let widths = try XCTUnwrap(golden["widths"]?.array?.compactMap(\.double))
    let documents = try XCTUnwrap(golden["documents"]?.object)
    XCTAssertEqual(Set(documents.keys), Set(Fixtures.documentNames), "every fixture document has goldens")
    var compared = 0
    for name in documents.keys {
      let document = try Fixtures.document(name)
      for width in widths {
        let expected = try XCTUnwrap(documents[name]?[String(Int(width))], "\(name)@\(width)")
        let actual = GridGeometry.layout(document, width: width) { node, width in
          GridGeometry.stubTextHeight(node, width: width)
        }
        let context = "\(name)@\(Int(width))"
        XCTAssertEqual(actual.breakpointId, expected["breakpointId"]?.string, context)
        XCTAssertEqual(actual.isFlow, expected["flow"]?.bool, context)
        assertClose(actual.cellSize, expected["cellSize"], "\(context) cellSize")
        assertClose(Double(actual.columns), expected["columns"], "\(context) columns")
        assertClose(Double(actual.rows), expected["rows"], "\(context) rows")
        assertClose(actual.padding, expected["padding"], "\(context) padding")
        assertClose(actual.canvasX, expected["canvas"]?["x"], "\(context) canvas.x")
        assertClose(actual.canvasWidth, expected["canvas"]?["width"], "\(context) canvas.width")
        assertClose(actual.canvasHeight, expected["canvas"]?["height"], "\(context) canvas.height")
        let nodes = try XCTUnwrap(expected["nodes"]?.array)
        XCTAssertEqual(actual.nodes.map(\.node.id), nodes.compactMap { $0["id"]?.string }, "\(context) paint order")
        for (placed, node) in zip(actual.nodes, nodes) {
          let id = "\(context) \(placed.node.id)"
          XCTAssertEqual(placed.isFlowing, node["flowing"]?.bool, id)
          assertClose(placed.rect.x, node["x"], "\(id).x")
          assertClose(placed.rect.y, node["y"], "\(id).y")
          assertClose(placed.rect.width, node["width"], "\(id).width")
          assertClose(placed.rect.height, node["height"], "\(id).height")
        }
        compared += 1
      }
    }
    XCTAssertGreaterThanOrEqual(compared, 200)
  }

  func testBreakpointSelectionAndClamping() throws {
    let document = try Fixtures.document("breakpoints-padding")
    XCTAssertEqual(GridGeometry.activeLayout(document, width: 599).breakpointId, nil)
    XCTAssertEqual(GridGeometry.activeLayout(document, width: 600).breakpointId, "tablet")
    XCTAssertEqual(GridGeometry.activeLayout(document, width: 1399.5).breakpointId, "desktop")
    XCTAssertEqual(GridGeometry.activeLayout(document, width: 5000).breakpointId, "wide")
    XCTAssertEqual(document.layoutOrder, ["tablet", "base", "desktop", "wide"])
    let bar = try XCTUnwrap(document.nodes.first { $0.id == "bar" })
    // Stored frames stay untouched; only the rendered frame is clamped.
    XCTAssertEqual(bar.frame.width, 80)
    XCTAssertEqual(GridGeometry.frame(of: bar, in: document.layout, breakpointId: nil), GridFrame(x: 0, y: 2, width: 6, height: 1))
  }

  private func assertClose(_ actual: Double, _ expected: JSONValue?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    guard let expected = expected?.double else {
      XCTFail("missing \(message)", file: file, line: line)
      return
    }
    XCTAssertEqual(actual, expected, accuracy: 1e-9 * max(1, abs(expected)), message, file: file, line: line)
  }
}
