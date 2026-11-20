import Foundation

/// A rectangle in points (CSS pixels), relative to the canvas.
public struct GridRect: Hashable, Sendable, Codable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double
  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

/// The layout selected for a container width.
public struct GridActiveLayout: Hashable, Sendable {
  public var layout: GridLayoutSettings
  /// `nil` for the base layout.
  public var breakpointId: String?
  public init(layout: GridLayoutSettings, breakpointId: String? = nil) {
    self.layout = layout
    self.breakpointId = breakpointId
  }
}

/// One laid-out node, in document (paint) order.
public struct GridPlacedNode: Hashable, Sendable {
  public var node: GridNode
  /// The clamped cell frame used for this layout.
  public var frame: GridFrame
  public var rect: GridRect
  /// True when the node is stacked by content flow (its X/width still come from the frame).
  public var isFlowing: Bool
  /// True when the node's height is its intrinsic text height.
  public var isContentSized: Bool
}

public struct GridCanvasGeometry: Hashable, Sendable {
  public var active: GridActiveLayout
  public var layout: GridLayoutSettings { active.layout }
  public var breakpointId: String { active.breakpointId ?? "base" }
  public var isFlow: Bool
  /// Rendered cell size (the authored size, or smaller to fit a narrow vertical container).
  public var cellSize: Double
  public var step: Double
  public var padding: Double
  public var columns: Int
  public var rows: Int
  /// Canvas size; `canvasX` centres it in a wider container, as the web renderer's `margin-inline: auto`.
  public var canvasX: Double
  public var canvasWidth: Double
  public var canvasHeight: Double
  public var nodes: [GridPlacedNode]
}

/// The UI-independent layout engine: a port of grid-core's geometry functions
/// and of the arithmetic `@nulldull/grid-react` expresses through inline styles
/// and CSS. Golden tests compare it with the TypeScript implementation.
public enum GridGeometry {
  /// `gridBounds`: omitted axis maximums use the 512-cell coordinate bound.
  public static func bounds(_ layout: GridLayoutSettings) -> (columns: Int, rows: Int) {
    (
      layout.direction == .vertical ? layout.columns : (layout.maxColumns ?? 512),
      layout.direction == .horizontal ? layout.rows : (layout.maxRows ?? 512)
    )
  }

  /// `gridFrame`: the breakpoint override (or base frame), clamped into the layout without rewriting it.
  public static func frame(of node: GridNode, in layout: GridLayoutSettings, breakpointId: String?) -> GridFrame {
    var f = node.frame
    if let breakpointId, let override = node.frames.first(where: { $0.id == breakpointId }) { f = override.frame }
    let (columns, rows) = bounds(layout)
    let width = min(f.width, columns)
    let height = min(f.height, rows)
    return GridFrame(x: min(f.x, columns - width), y: min(f.y, rows - height), width: width, height: height)
  }

  /// `gridLayoutAt`: the breakpoint with the largest `minWidth` not above `width`, else the base layout.
  public static func activeLayout(_ document: GridDocument, width: Double) -> GridActiveLayout {
    let match = document.breakpoints
      .sorted { $0.minWidth > $1.minWidth }
      .first { Double($0.minWidth) <= width }
    return GridActiveLayout(layout: match?.layout ?? document.layout, breakpointId: match?.id)
  }

  /// `gridCellSize`: vertical grids shrink cells to fit the container, never below 8 points.
  public static func cellSize(_ layout: GridLayoutSettings, width: Double) -> Double {
    guard layout.direction == .vertical else { return Double(layout.cellSize) }
    let padding = Double(layout.padding ?? 0)
    let available = (width - padding * 2 - Double(layout.gap) * Double(layout.columns - 1)) / Double(layout.columns)
    return min(Double(layout.cellSize), max(8, available))
  }

  /// Lays out `document` for a container `width`.
  ///
  /// - Parameters:
  ///   - active: an explicit layout (the renderer's `layout`/`breakpointId` override); defaults to `activeLayout`.
  ///   - measure: the intrinsic height of a flowing text node at a given width. Only called in content-flow layouts.
  public static func layout(
    _ document: GridDocument, width viewport: Double, active: GridActiveLayout? = nil,
    measure: (GridBuiltinNode, Double) -> Double
  ) -> GridCanvasGeometry {
    let active = active ?? activeLayout(document, width: viewport)
    let layout = active.layout
    let visible = document.nodes.filter { !$0.hidden }.map {
      ($0, frame(of: $0, in: layout, breakpointId: active.breakpointId))
    }
    let (boundColumns, boundRows) = bounds(layout)
    let cell = cellSize(layout, width: viewport)
    let gap = Double(layout.gap)
    let step = cell + gap
    let padding = Double(layout.padding ?? 0)
    let columns =
      layout.direction == .vertical
      ? boundColumns : min(boundColumns, max(1, visible.map { $0.1.x + $0.1.width }.max() ?? 1))
    let rows =
      layout.direction == .horizontal
      ? boundRows : min(boundRows, max(1, visible.map { $0.1.y + $0.1.height }.max() ?? 1))
    func absolute(_ f: GridFrame) -> GridRect {
      GridRect(
        x: padding + Double(f.x) * step, y: padding + Double(f.y) * step,
        width: Double(f.width) * step - gap, height: Double(f.height) * step - gap)
    }

    var placed: [GridPlacedNode] = []
    let canvasWidth: Double
    let canvasHeight: Double
    if let flowGap = layout.flowGap.map(Double.init) {
      let maxWidth = Double(columns) * (Double(layout.cellSize) + gap) - gap + padding * 2
      canvasWidth = min(viewport, maxWidth)
      let content = max(0, canvasWidth - padding * 2)
      var cursor = padding
      var count = 0
      for (node, f) in visible {
        if node.ignoresFlow {
          placed.append(GridPlacedNode(node: node, frame: f, rect: absolute(f), isFlowing: false, isContentSized: false))
          continue
        }
        let width = max(0, (content + gap) * (Double(f.width) / Double(columns)) - gap)
        let text = node.builtin.flatMap { $0.kind == .text ? $0 : nil }
        let height = text.map { measure($0, width) } ?? (Double(f.height) * step - gap)
        if count > 0 { cursor += flowGap }
        count += 1
        let rect = GridRect(
          x: padding + (content + gap) * (Double(f.x) / Double(columns)), y: cursor, width: width, height: height)
        placed.append(GridPlacedNode(node: node, frame: f, rect: rect, isFlowing: true, isContentSized: text != nil))
        cursor += height
      }
      let minHeight = visible.filter { $0.0.ignoresFlow }
        .map { Double($0.1.y + $0.1.height) * step - gap + padding * 2 }
        .reduce(0, max)
      canvasHeight = max(minHeight, cursor + padding)
    } else {
      canvasWidth = Double(columns) * step - gap + padding * 2
      canvasHeight = Double(rows) * step - gap + padding * 2
      for (node, f) in visible {
        placed.append(GridPlacedNode(node: node, frame: f, rect: absolute(f), isFlowing: false, isContentSized: false))
      }
    }
    return GridCanvasGeometry(
      active: active, isFlow: layout.flowGap != nil, cellSize: cell, step: step, padding: padding, columns: columns,
      rows: rows, canvasX: max(0, (viewport - canvasWidth) / 2), canvasWidth: canvasWidth, canvasHeight: canvasHeight,
      nodes: placed)
  }

  /// The deterministic text height used by the shared golden fixtures
  /// (`fixtures/grid-renderer/golden/layout.json`; see `fixtures/README.md`). Not a typographic measurement.
  public static func stubTextHeight(_ node: GridBuiltinNode, width: Double) -> Double {
    let pad = Double(node.appearance.padding ?? 8)
    let fontSize = Double(node.fontSize)
    let inner = max(1, width - 2 * pad)
    let perLine = max(1, (inner / (fontSize * 0.5)).rounded(.down))
    let lines = max(1, (Double(node.text.utf16.count) / perLine).rounded(.up))
    return 2 * pad + lines * (fontSize * (node.lineHeight ?? 1.2))
  }
}
