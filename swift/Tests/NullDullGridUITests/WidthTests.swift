import SwiftUI
import XCTest

@testable import NullDullGrid
@testable import NullDullGridUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// `GridView` without `width:` must follow the width its parent proposes, narrower or wider than
/// the canvas it currently shows. The golden tests only lay out at fixed widths.
@available(iOS 16, macOS 13, tvOS 16, *)
@MainActor
final class WidthTests: XCTestCase {
  func document() throws -> GridDocument {
    try GridDocument(json: Data(contentsOf: RenderTests.fixtures.appendingPathComponent("documents/flow-mixed.json")))
  }

  func testExplicitWidthWinsThenMeasuredThenInitial() {
    XCTAssertEqual(GridView.viewport(width: 500, measured: 300, initialWidth: 390), 500)
    XCTAssertEqual(GridView.viewport(width: nil, measured: 300, initialWidth: 390), 300)
    XCTAssertEqual(GridView.viewport(width: nil, measured: nil, initialWidth: 390), 390)
  }

  /// Before the fix, a canvas wider than the proposal (390 in a 370 container, or 718 after
  /// rotating back to 390) widened the measuring frame, so the measured width could only grow.
  func testGridViewIsAsWideAsTheProposalNotItsCanvas() throws {
    let document = try document()
    for proposed in [200, 370, 390, 718] as [CGFloat] {
      let size = fittingSize(GridView(document: document), width: proposed)
      XCTAssertEqual(size.width, proposed, accuracy: 0.5, "proposed \(proposed)")
    }
    // An explicit width is unchanged: the view is exactly that wide.
    XCTAssertEqual(fittingSize(GridView(document: document, width: 500), width: 370).width, 500, accuracy: 0.5)
  }

  func testReportsTheProposedWidthAsItShrinksAndGrows() {
    var reported: [CGFloat] = []
    // A rigid child, like the canvas laid out at its previous width.
    let view = Color.clear.frame(width: 390, height: 10).readingProposedWidth { reported.append($0) }
    let host = Host(view)
    for width in [370, 718, 390, 300, 900] as [CGFloat] {
      host.layout(width: width)
      XCTAssertEqual(reported.last ?? 0, width, accuracy: 0.5, "after resizing to \(width): \(reported)")
    }
  }

  /// With no width proposal (a horizontal `ScrollView`, `fixedSize`) the canvas width is kept.
  func testWithoutAWidthProposalTheChildWidthIsKept() throws {
    let renderer = ImageRenderer(content: Color.red.frame(width: 390, height: 10).readingProposedWidth { _ in })
    renderer.proposedSize = .unspecified
    renderer.scale = 1
    XCTAssertEqual(try XCTUnwrap(renderer.cgImage).width, 390)
  }

  /// The README usage (no `width:`, in a vertical `ScrollView`) resized wide, then narrower than
  /// `initialWidth`: after each resize the canvas lays out at the new width, so its height matches
  /// the same document rendered with an explicit `width:`.
  func testDefaultUsageShrinksAfterGrowingWithExplicitWidthHeights() throws {
    let document = try document()
    func explicitHeight(_ width: CGFloat) -> CGFloat {
      fittingSize(GridView(document: document, width: width).fixedSize(horizontal: false, vertical: true), width: width).height
    }
    var heights: [CGFloat] = []
    let host = Host(
      ScrollView {
        GridView(document: document)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights.append($0) }
      })
    // The fixture's height depends on the width (breakpoint and text wrapping), so a stale canvas
    // laid out at the previous width would show a different height.
    XCTAssertGreaterThan(abs(explicitHeight(260) - explicitHeight(718)), 0.5)
    XCTAssertGreaterThan(abs(explicitHeight(260) - explicitHeight(390)), 0.5)
    for width in [718, 390, 300, 260, 718, 260] as [CGFloat] {
      host.layout(width: width)
      XCTAssertEqual(heights.last ?? 0, explicitHeight(width), accuracy: 0.5, "after resizing to \(width): \(heights)")
    }
  }

  func fittingSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
    let fit = CGSize(width: width, height: .infinity)
    #if canImport(AppKit)
    return NSHostingController(rootView: view).sizeThatFits(in: fit)
    #else
    return UIHostingController(rootView: view).sizeThatFits(in: fit)
    #endif
  }

  /// A hosting view resized like a window or a rotating screen.
  @MainActor
  final class Host {
    #if canImport(AppKit)
    let view: NSView
    init<V: View>(_ root: V) { view = NSHostingView(rootView: root) }
    #else
    let controller: UIViewController
    let window: UIWindow
    var view: UIView { controller.view }
    init<V: View>(_ root: V) {
      controller = UIHostingController(rootView: root)
      if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
        window = UIWindow(windowScene: scene)
      } else {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 300))
      }
      // Geometry callbacks and stateful nodes need a mounted UIKit hierarchy. Resize the child
      // hosting view independently of the simulated screen.
      let parent = UIViewController()
      window.rootViewController = parent
      parent.addChild(controller)
      parent.view.addSubview(controller.view)
      controller.didMove(toParent: parent)
      window.isHidden = false
    }
    #endif

    func layout(width: CGFloat) {
      view.frame = CGRect(x: 0, y: 0, width: width, height: 100)
      for _ in 0..<3 {
        #if canImport(AppKit)
        view.layoutSubtreeIfNeeded()
        #else
        view.layoutIfNeeded()
        #endif
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      }
    }
  }
}
