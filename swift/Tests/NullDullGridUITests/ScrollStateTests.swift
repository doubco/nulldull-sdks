import SwiftUI
import XCTest

@testable import NullDullGrid
@testable import NullDullGridUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A horizontal canvas scrolls when it is wider than the view and sits still when it fits. Crossing
/// that width (rotation, window resizing) must not rebuild the node views, or a tapped embed would
/// go back to its poster and every node would lose its state.
@available(iOS 16, macOS 13, tvOS 16, *)
@MainActor
final class ScrollStateTests: XCTestCase {
  /// Counts the node views SwiftUI creates: `@StateObject` builds its object once per view identity.
  final class Instances: ObservableObject {
    nonisolated(unsafe) static var created = 0
    init() { Self.created += 1 }
  }

  struct StatefulNode: View {
    @StateObject private var instance = Instances()
    var body: some View { Color.orange }
  }

  var registry: GridCustomNodeRegistry {
    GridCustomNodeRegistry().register("stateful") { _ in StatefulNode() }
  }

  /// `direction` horizontal: 17 columns of 40 pt with a 4 pt gap and 10 pt padding are 764 pt wide.
  /// Vertical and flow layouts fit their columns to the width instead.
  func document(_ layout: String) throws -> GridDocument {
    let json = """
      {
        "layout": \(layout),
        "breakpoints": [],
        "nodes": [{
          "id": "n", "kind": "custom", "name": "Stateful", "hidden": false,
          "frame": { "x": 0, "y": 0, "width": 17, "height": 2 }, "frames": {},
          "nodeKey": "stateful", "properties": []
        }]
      }
      """
    return try GridDocument(json: Data(json.utf8))
  }

  static let horizontal = #"{ "direction": "horizontal", "columns": 4, "rows": 4, "cellSize": 40, "gap": 4, "padding": 10, "maxColumns": 30 }"#
  static let vertical = #"{ "direction": "vertical", "columns": 20, "rows": 4, "cellSize": 40, "gap": 4, "padding": 10 }"#
  static let flow = #"{ "direction": "vertical", "columns": 20, "rows": 4, "cellSize": 40, "gap": 4, "padding": 10, "flowGap": 8 }"#

  func testHorizontalCanvasWidth() throws {
    let geometry = GridGeometry.layout(try document(Self.horizontal), width: 700) { _, _ in 0 }
    XCTAssertEqual(geometry.canvasWidth, 764)
  }

  /// The scroll view is as tall as the canvas whether or not the canvas fits, not as tall as its container.
  func testHorizontalGridIsAsTallAsItsCanvas() throws {
    let document = try document(Self.horizontal)
    for width in [700, 800] as [CGFloat] {
      let fit = CGSize(width: width, height: 600)
      #if canImport(AppKit)
      let size = NSHostingController(rootView: GridView(document: document, width: width)).sizeThatFits(in: fit)
      #else
      let size = UIHostingController(rootView: GridView(document: document, width: width)).sizeThatFits(in: fit)
      #endif
      XCTAssertEqual(size.width, width, accuracy: 0.5)
      XCTAssertEqual(size.height, 4 * 44 - 4 + 20, accuracy: 0.5, "at \(width)")
    }
  }

  /// Wider than the canvas, narrower (it scrolls), and back: the node keeps its state throughout.
  func testNodeStateSurvivesCrossingTheCanvasWidth() throws {
    for (name, layout) in [("horizontal", Self.horizontal), ("vertical", Self.vertical), ("flow", Self.flow)] {
      let document = try document(layout)
      Instances.created = 0
      let host = WidthTests.Host(ScrollView { GridView(document: document, customNodes: registry) })
      for width in [800, 700, 800, 700, 900, 400] as [CGFloat] {
        host.layout(width: width)
        XCTAssertEqual(Instances.created, 1, "\(name) after resizing to \(width)")
      }
    }
  }

  /// An app that passes the measured width itself, which may change: same result.
  func testNodeStateSurvivesAnExplicitWidthCrossingTheCanvasWidth() throws {
    let document = try document(Self.horizontal)
    final class Width: ObservableObject { @Published var value: CGFloat = 800 }
    struct Root: View {
      let document: GridDocument
      let registry: GridCustomNodeRegistry
      @ObservedObject var width: Width
      var body: some View { GridView(document: document, width: width.value, customNodes: registry) }
    }
    let width = Width()
    Instances.created = 0
    let host = WidthTests.Host(Root(document: document, registry: registry, width: width))
    for value in [800, 700, 800, 700] as [CGFloat] {
      width.value = value
      host.layout(width: value)
      XCTAssertEqual(Instances.created, 1, "after width \(value)")
    }
  }

  #if canImport(AppKit)
  /// The horizontal canvas scrolls with the wheel or trackpad only while it is wider than the view,
  /// and passes vertical scrolling to the page around it.
  func testScrollsOnlyWhileTheCanvasIsWider() throws {
    let document = try document(Self.horizontal)
    var origin = CGPoint(x: CGFloat.nan, y: .nan)
    let registry = GridCustomNodeRegistry().register("stateful") { _ in
      Color.orange.onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
    }
    let host = WidthTests.Host(
      ScrollView {
        VStack(spacing: 0) {
          GridView(document: document, customNodes: registry)
          Color.clear.frame(height: 1000)
        }
      })
    // Scroll events reach a scroll view only in a window.
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 300), styleMask: [], backing: .buffered, defer: false)
    window.contentView = host.view
    func scrollViews(_ view: NSView) -> [NSScrollView] {
      ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }
    /// The innermost scroll view under the canvas receives the event, as from a trackpad over it.
    func scroll(dx: CGFloat = 0, dy: CGFloat = 0) throws {
      let event = try XCTUnwrap(
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(-dy), wheel2: Int32(-dx), wheel3: 0))
      try XCTUnwrap(scrollViews(host.view).last).scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: event)))
      host.layout(width: host.view.frame.width)
    }

    host.layout(width: 700)
    XCTAssertEqual(scrollViews(host.view).count, 2, "the page and the canvas")
    XCTAssertEqual(origin.x, 10, accuracy: 0.5)
    try scroll(dx: 40)
    XCTAssertEqual(origin.x, -30, accuracy: 0.5, "a canvas 764 pt wide scrolls in 700 pt")

    host.layout(width: 800)
    XCTAssertEqual(scrollViews(host.view).count, 2)
    // A persistent vertical scrollbar takes width from the outer scroll view’s clip view.
    // GridView centres the 764 pt canvas inside that viewport. The node starts at its 10 pt padding.
    let viewportWidth = try XCTUnwrap(scrollViews(host.view).first).contentView.bounds.width
    let centredOrigin = (viewportWidth - 764) / 2 + 10
    XCTAssertEqual(origin.x, centredOrigin, accuracy: 0.5, "the fitting canvas is centred, back at its start")
    try scroll(dx: 40)
    XCTAssertEqual(origin.x, centredOrigin, accuracy: 0.5, "a fitting canvas does not scroll")
    let top = origin.y
    try scroll(dy: 50)
    XCTAssertEqual(origin.y, top - 50, accuracy: 0.5, "vertical scrolling over the canvas moves the page")
  }
  #endif
}
