import Foundation

/// Cell coordinates. Zero-based; widths and heights are in cells.
public struct GridFrame: Hashable, Sendable, Codable {
  public var x: Int
  public var y: Int
  public var width: Int
  public var height: Int
  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public enum GridDirection: String, Sendable, Codable, CaseIterable { case vertical, horizontal }
public enum GridFit: String, Sendable, Codable, CaseIterable { case cover, contain, tile }
public enum GridAlign: String, Sendable, Codable, CaseIterable { case left, center, right, justify }
public enum GridVerticalAlign: String, Sendable, Codable, CaseIterable { case top, middle, bottom }
public enum GridFontFamily: String, Sendable, Codable, CaseIterable { case system, rounded, sans, serif, mono }
public enum GridBorderStyle: String, Sendable, Codable, CaseIterable { case solid, dashed, dotted, double, groove, ridge }
public enum GridStrokeStyle: String, Sendable, Codable, CaseIterable { case solid, dashed, dotted }
public enum GridSeparatorStyle: String, Sendable, Codable, CaseIterable { case empty, full, centered }
public enum GridBuiltinKind: String, Sendable, Codable, CaseIterable {
  case text, image, video, audio, shape, embed, separator
}
public enum GridShape: String, Sendable, Codable, CaseIterable {
  case rectangle, ellipse, circle, triangle, pentagon, hexagon, heptagon, octagon, polygon, star, line, arrow, icon, svg
}

/// A validated colour: `transparent` (inherit the theme / no fill) or `#rrggbb`.
public struct GridColor: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String
  /// Nil for `transparent`.
  public let rgb: (red: Double, green: Double, blue: Double)?

  public init?(_ value: String) {
    if value == "transparent" {
      rawValue = value
      rgb = nil
      return
    }
    let hex = Array(value.utf8)
    guard hex.count == 7, hex[0] == UInt8(ascii: "#"), let number = UInt32(String(value.dropFirst()), radix: 16),
      hex.dropFirst().allSatisfy({ (0x30...0x39).contains($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0) })
    else { return nil }
    rawValue = value
    rgb = (Double((number >> 16) & 0xFF) / 255, Double((number >> 8) & 0xFF) / 255, Double(number & 0xFF) / 255)
  }
  public static let transparent = GridColor("transparent")!
  public var isTransparent: Bool { rgb == nil }
  public var description: String { rawValue }
  public static func == (a: GridColor, b: GridColor) -> Bool { a.rawValue == b.rawValue }
  public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

/// Optional appearance shared by layouts and built-in nodes. All opacities are 0–1 and default to 1.
public struct GridAppearance: Hashable, Sendable {
  /// `nil`: absent. `.some(nil)`: explicitly cleared (`null`).
  public var backgroundImageId: String??
  public var backgroundFit: GridFit?
  public var padding: Int?
  public var colorOpacity: Double?
  public var backgroundOpacity: Double?
  public init(
    backgroundImageId: String?? = nil, backgroundFit: GridFit? = nil, padding: Int? = nil,
    colorOpacity: Double? = nil, backgroundOpacity: Double? = nil
  ) {
    self.backgroundImageId = backgroundImageId
    self.backgroundFit = backgroundFit
    self.padding = padding
    self.colorOpacity = colorOpacity
    self.backgroundOpacity = backgroundOpacity
  }
  /// The referenced background image, if any.
  public var backgroundImage: String? { backgroundImageId ?? nil }
}

/// The geometry and appearance of the base layout or a breakpoint.
public struct GridLayoutSettings: Hashable, Sendable {
  public var flowGap: Int?
  public var appearance: GridAppearance
  /// Editor viewport metadata only; never constrains public pages.
  public var previewWidth: Int?
  public var previewHeight: Int?
  public var background: GridColor?
  public var color: GridColor?
  public var radius: Int?
  public var direction: GridDirection
  public var columns: Int
  public var rows: Int
  public var cellSize: Int
  public var gap: Int
  public var maxRows: Int?
  public var maxColumns: Int?

  public init(
    direction: GridDirection = .vertical, columns: Int = 10, rows: Int = 8, cellSize: Int = 32, gap: Int = 0,
    flowGap: Int? = nil, appearance: GridAppearance = GridAppearance(), previewWidth: Int? = nil,
    previewHeight: Int? = nil, background: GridColor? = nil, color: GridColor? = nil, radius: Int? = nil,
    maxRows: Int? = nil, maxColumns: Int? = nil
  ) {
    self.direction = direction
    self.columns = columns
    self.rows = rows
    self.cellSize = cellSize
    self.gap = gap
    self.flowGap = flowGap
    self.appearance = appearance
    self.previewWidth = previewWidth
    self.previewHeight = previewHeight
    self.background = background
    self.color = color
    self.radius = radius
    self.maxRows = maxRows
    self.maxColumns = maxColumns
  }

  public var padding: Int? { appearance.padding }
  /// Whether this layout stacks visible nodes in document order.
  public var isFlow: Bool { flowGap != nil }
}

public struct GridBreakpoint: Hashable, Sendable {
  public var layout: GridLayoutSettings
  public var id: String
  public var name: String
  public var minWidth: Int
  public init(layout: GridLayoutSettings, id: String, name: String, minWidth: Int) {
    self.layout = layout
    self.id = id
    self.name = name
    self.minWidth = minWidth
  }
}

/// A built-in node. Optional fields are absent unless the document sets them.
public struct GridBuiltinNode: Hashable, Sendable {
  public var appearance = GridAppearance()
  public var dropcap: Bool?
  public var fitToBox: Bool?
  public var ignoreFlow: Bool?
  public var opacity: Double?
  public var borderOpacity: Double?
  public var strokeOpacity: Double?
  public var borderColor: GridColor?
  public var strokeColor: GridColor?
  public var borderWidth: Int?
  public var strokeWidth: Int?
  public var borderStyle: GridBorderStyle?
  public var strokeStyle: GridStrokeStyle?
  /// Normalized http(s) URL, or an empty string.
  public var link: String?
  public var url: String?
  public var rotation: Double?
  public var lineHeight: Double?
  /// `nil`: absent. `.some(nil)`: explicitly cleared (`null`).
  public var fontAssetId: String??
  public var fontFamily: GridFontFamily?
  public var verticalAlign: GridVerticalAlign?
  public var iconName: String?
  public var polygonSides: Int?
  /// Present on separators only (defaults to `.empty` there).
  public var separatorStyle: GridSeparatorStyle?
  public var id: String
  public var kind: GridBuiltinKind
  public var name: String
  public var text: String
  public var assetId: String?
  public var frame: GridFrame
  /// Per-breakpoint frame overrides, keyed by breakpoint ID, in document order.
  public var frames: [(id: String, frame: GridFrame)]
  public var color: GridColor
  public var background: GridColor
  public var fontSize: Int
  public var radius: Int
  public var align: GridAlign
  public var fit: GridFit
  public var shape: GridShape
  public var hidden: Bool

  public init(
    id: String, kind: GridBuiltinKind, name: String = "", text: String = "", assetId: String? = nil,
    frame: GridFrame, frames: [(id: String, frame: GridFrame)] = [], color: GridColor = .transparent,
    background: GridColor = .transparent, fontSize: Int = 24, radius: Int = 8, align: GridAlign = .left,
    fit: GridFit = .cover, shape: GridShape = .rectangle, hidden: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.text = text
    self.assetId = assetId
    self.frame = frame
    self.frames = frames
    self.color = color
    self.background = background
    self.fontSize = fontSize
    self.radius = radius
    self.align = align
    self.fit = fit
    self.shape = shape
    self.hidden = hidden
  }

  public var fontAsset: String? { fontAssetId ?? nil }

  public static func == (a: GridBuiltinNode, b: GridBuiltinNode) -> Bool {
    JSONValue.object(a.json) == JSONValue.object(b.json)
  }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A host-rendered node. Its properties are inert strings: never markup, code or asset references.
public struct GridCustomNode: Hashable, Sendable {
  public struct Property: Hashable, Sendable, Codable {
    public var key: String
    public var value: String
    public init(key: String, value: String) {
      self.key = key
      self.value = value
    }
  }
  public var ignoreFlow: Bool?
  public var id: String
  public var name: String
  public var frame: GridFrame
  public var frames: [(id: String, frame: GridFrame)]
  public var hidden: Bool
  public var opacity: Double
  public var nodeKey: String
  public var properties: [Property]

  public init(
    id: String, name: String = "Custom", frame: GridFrame, frames: [(id: String, frame: GridFrame)] = [],
    hidden: Bool = false, opacity: Double = 0.5, nodeKey: String, properties: [Property] = [],
    ignoreFlow: Bool? = nil
  ) {
    self.id = id
    self.name = name
    self.frame = frame
    self.frames = frames
    self.hidden = hidden
    self.opacity = opacity
    self.nodeKey = nodeKey
    self.properties = properties
    self.ignoreFlow = ignoreFlow
  }

  /// The first value stored under `key`.
  public subscript(property key: String) -> String? { properties.first { $0.key == key }?.value }

  public static func == (a: GridCustomNode, b: GridCustomNode) -> Bool {
    JSONValue.object(a.json) == JSONValue.object(b.json)
  }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum GridNode: Hashable, Sendable {
  case builtin(GridBuiltinNode)
  case custom(GridCustomNode)

  public var id: String {
    switch self {
    case .builtin(let node): node.id
    case .custom(let node): node.id
    }
  }
  public var name: String {
    switch self {
    case .builtin(let node): node.name
    case .custom(let node): node.name
    }
  }
  public var frame: GridFrame {
    switch self {
    case .builtin(let node): node.frame
    case .custom(let node): node.frame
    }
  }
  public var frames: [(id: String, frame: GridFrame)] {
    switch self {
    case .builtin(let node): node.frames
    case .custom(let node): node.frames
    }
  }
  public var hidden: Bool {
    switch self {
    case .builtin(let node): node.hidden
    case .custom(let node): node.hidden
    }
  }
  public var ignoresFlow: Bool {
    switch self {
    case .builtin(let node): node.ignoreFlow ?? false
    case .custom(let node): node.ignoreFlow ?? false
    }
  }
  /// Whole-node opacity (custom nodes store one; built-ins default to 1).
  public var opacity: Double {
    switch self {
    case .builtin(let node): node.opacity ?? 1
    case .custom(let node): node.opacity
    }
  }
  public var builtin: GridBuiltinNode? {
    if case .builtin(let node) = self { return node }
    return nil
  }
  public var custom: GridCustomNode? {
    if case .custom(let node) = self { return node }
    return nil
  }
  /// Whether this node takes its intrinsic height in a content-flow layout.
  public var isText: Bool { builtin?.kind == .text }
}

/// A validated Grid document, as the public API delivers it.
public struct GridDocument: Hashable, Sendable {
  public var layout: GridLayoutSettings
  public var breakpoints: [GridBreakpoint]
  public var nodes: [GridNode]
  public var baseLayoutName: String?
  /// Display position only; Base remains the fallback below every breakpoint threshold.
  public var baseLayoutIndex: Int?

  public init(
    layout: GridLayoutSettings, breakpoints: [GridBreakpoint] = [], nodes: [GridNode] = [], baseLayoutName: String? = nil,
    baseLayoutIndex: Int? = nil
  ) {
    self.layout = layout
    self.breakpoints = breakpoints
    self.nodes = nodes
    self.baseLayoutName = baseLayoutName
    self.baseLayoutIndex = baseLayoutIndex
  }

  /// Layout IDs in display order, with `base` inserted at `baseLayoutIndex`.
  public var layoutOrder: [String] {
    var ids = breakpoints.map(\.id)
    ids.insert("base", at: min(baseLayoutIndex ?? 0, ids.count))
    return ids
  }

  /// Every referenced upload, as grid-core's `gridAssetReferences` lists them.
  public var assetReferences: [(id: String, kind: String)] {
    var result: [(String, String)] = []
    for layout in [layout] + breakpoints.map(\.layout) {
      if let id = layout.appearance.backgroundImage { result.append((id, "image")) }
    }
    for case .builtin(let node) in nodes {
      if let id = node.fontAsset { result.append((id, "font")) }
      if let id = node.appearance.backgroundImage { result.append((id, "image")) }
      if let id = node.assetId { result.append((id, node.kind == .shape ? "image" : node.kind.rawValue)) }
    }
    return result
  }
}

// MARK: - Codable

extension GridDocument: Codable {
  /// Decodes and validates exactly like `validateGrid`; unknown fields are ignored.
  public init(from decoder: Decoder) throws {
    self = try GridValidator.validate(JSONValue(from: decoder))
  }
  public func encode(to encoder: Encoder) throws {
    try JSONValue.object(json).encode(to: encoder)
  }

  /// Validates JSON text.
  public init(json data: Data) throws {
    let value: JSONValue
    do { value = try JSONValue.parse(data) } catch { throw GridValidationError("Expected an object.") }
    self = try GridValidator.validate(value)
  }

  /// The normalized document, with keys in the order `validateGrid` returns them.
  public var json: JSONObject {
    var object = JSONObject()
    object["layout"] = .object(layout.json)
    object["breakpoints"] = .array(breakpoints.map { .object($0.json) })
    object["nodes"] = .array(nodes.map { .object($0.json) })
    if let baseLayoutName { object["baseLayoutName"] = .string(baseLayoutName) }
    if let baseLayoutIndex { object["baseLayoutIndex"] = .number(Double(baseLayoutIndex)) }
    return object
  }
  /// `JSON.stringify` of the normalized document.
  public var jsonString: String { JSONValue.object(json).javaScriptJSON }
}

extension GridAppearance {
  func write(into object: inout JSONObject) {
    if let backgroundImageId {
      object["backgroundImageId"] = backgroundImageId.map(JSONValue.string) ?? .null
    }
    if let backgroundFit { object["backgroundFit"] = .string(backgroundFit.rawValue) }
    if let padding { object["padding"] = .number(Double(padding)) }
    if let colorOpacity { object["colorOpacity"] = .number(colorOpacity) }
    if let backgroundOpacity { object["backgroundOpacity"] = .number(backgroundOpacity) }
  }
}

extension GridLayoutSettings {
  public var json: JSONObject {
    var object = JSONObject()
    if let flowGap { object["flowGap"] = .number(Double(flowGap)) }
    appearance.write(into: &object)
    if let previewWidth { object["previewWidth"] = .number(Double(previewWidth)) }
    if let previewHeight { object["previewHeight"] = .number(Double(previewHeight)) }
    if let background { object["background"] = .string(background.rawValue) }
    if let color { object["color"] = .string(color.rawValue) }
    if let radius { object["radius"] = .number(Double(radius)) }
    object["direction"] = .string(direction.rawValue)
    object["columns"] = .number(Double(columns))
    object["rows"] = .number(Double(rows))
    object["cellSize"] = .number(Double(cellSize))
    object["gap"] = .number(Double(gap))
    if let maxRows { object["maxRows"] = .number(Double(maxRows)) }
    if let maxColumns { object["maxColumns"] = .number(Double(maxColumns)) }
    return object
  }
}

extension GridBreakpoint {
  public var json: JSONObject {
    var object = layout.json
    object["id"] = .string(id)
    object["name"] = .string(name)
    object["minWidth"] = .number(Double(minWidth))
    return object
  }
}

extension GridFrame {
  var json: JSONValue {
    .object(JSONObject([
      ("x", .number(Double(x))), ("y", .number(Double(y))),
      ("width", .number(Double(width))), ("height", .number(Double(height))),
    ]))
  }
}

func framesJSON(_ frames: [(id: String, frame: GridFrame)]) -> JSONValue {
  .object(JSONObject(frames.map { ($0.id, $0.frame.json) }))
}

extension GridBuiltinNode {
  public var json: JSONObject {
    var object = JSONObject()
    appearance.write(into: &object)
    if let dropcap { object["dropcap"] = .bool(dropcap) }
    if let fitToBox { object["fitToBox"] = .bool(fitToBox) }
    if let ignoreFlow { object["ignoreFlow"] = .bool(ignoreFlow) }
    if let opacity { object["opacity"] = .number(opacity) }
    if let borderOpacity { object["borderOpacity"] = .number(borderOpacity) }
    if let strokeOpacity { object["strokeOpacity"] = .number(strokeOpacity) }
    if let borderColor { object["borderColor"] = .string(borderColor.rawValue) }
    if let strokeColor { object["strokeColor"] = .string(strokeColor.rawValue) }
    if let borderWidth { object["borderWidth"] = .number(Double(borderWidth)) }
    if let strokeWidth { object["strokeWidth"] = .number(Double(strokeWidth)) }
    if let borderStyle { object["borderStyle"] = .string(borderStyle.rawValue) }
    if let strokeStyle { object["strokeStyle"] = .string(strokeStyle.rawValue) }
    if let link { object["link"] = .string(link) }
    if let url { object["url"] = .string(url) }
    if let rotation { object["rotation"] = .number(rotation) }
    if let lineHeight { object["lineHeight"] = .number(lineHeight) }
    if let fontAssetId { object["fontAssetId"] = fontAssetId.map(JSONValue.string) ?? .null }
    if let fontFamily { object["fontFamily"] = .string(fontFamily.rawValue) }
    if let verticalAlign { object["verticalAlign"] = .string(verticalAlign.rawValue) }
    if let iconName { object["iconName"] = .string(iconName) }
    if let polygonSides { object["polygonSides"] = .number(Double(polygonSides)) }
    if let separatorStyle { object["separatorStyle"] = .string(separatorStyle.rawValue) }
    object["id"] = .string(id)
    object["kind"] = .string(kind.rawValue)
    object["name"] = .string(name)
    object["text"] = .string(text)
    object["assetId"] = assetId.map(JSONValue.string) ?? .null
    object["frame"] = frame.json
    object["frames"] = framesJSON(frames)
    object["color"] = .string(color.rawValue)
    object["background"] = .string(background.rawValue)
    object["fontSize"] = .number(Double(fontSize))
    object["radius"] = .number(Double(radius))
    object["align"] = .string(align.rawValue)
    object["fit"] = .string(fit.rawValue)
    object["shape"] = .string(shape.rawValue)
    object["hidden"] = .bool(hidden)
    return object
  }
}

extension GridCustomNode {
  public var json: JSONObject {
    var object = JSONObject()
    if let ignoreFlow { object["ignoreFlow"] = .bool(ignoreFlow) }
    object["id"] = .string(id)
    object["kind"] = .string("custom")
    object["name"] = .string(name)
    object["frame"] = frame.json
    object["frames"] = framesJSON(frames)
    object["hidden"] = .bool(hidden)
    object["opacity"] = .number(opacity)
    object["nodeKey"] = .string(nodeKey)
    object["properties"] = .array(properties.map {
      .object(JSONObject([("key", .string($0.key)), ("value", .string($0.value))]))
    })
    return object
  }
}

extension GridNode {
  public var json: JSONObject {
    switch self {
    case .builtin(let node): node.json
    case .custom(let node): node.json
    }
  }
}
