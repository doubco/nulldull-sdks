import Foundation

/// A document rejected by validation. Messages match `@nulldull/grid-core`'s `validateGrid`.
public struct GridValidationError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var description: String { message }
  public var errorDescription: String? { message }
}

public enum GridLimits {
  public static let maxFonts = 8
  public static let fontMaxBytes = 2 * 1024 * 1024
  public static let nodeNameLimit = 160
  public static let maxBreakpoints = 12
  public static let maxNodes = 200
  public static let maxDocumentBytes = 180_000
  public static let svgMaxBytes = 1024 * 1024
}

/// A port of `validateGrid`: the same checks, in the same order, with the same
/// messages and normalization. Unknown fields are ignored; malformed known
/// fields reject the whole document.
public enum GridValidator {
  public static func validate(_ value: JSONValue) throws -> GridDocument {
    let o = try object(value)
    let base = try layout(o["layout"])
    guard case .array(let rawBreakpoints)? = o["breakpoints"], rawBreakpoints.count <= GridLimits.maxBreakpoints,
      case .array(let rawNodes)? = o["nodes"], rawNodes.count <= GridLimits.maxNodes
    else { throw GridValidationError("Use up to 12 breakpoints and 200 nodes.") }
    let breakpoints = try rawBreakpoints.map { value -> GridBreakpoint in
      let b = try object(value)
      let layout = try layout(value)
      return GridBreakpoint(
        layout: layout, id: try gridId(b["id"]), name: try text(b["name"], 80, "Breakpoint name"),
        minWidth: try integer(b["minWidth"], 1, 7680, "Breakpoint width"))
    }
    if Set(breakpoints.map(\.id)).count != breakpoints.count || Set(breakpoints.map(\.minWidth)).count != breakpoints.count {
      throw GridValidationError("Breakpoint IDs and widths must be unique.")
    }
    let breakpointIds = Set(breakpoints.map(\.id))
    let nodes = try rawNodes.map { try node($0, breakpointIds: breakpointIds) }
    if Set(nodes.map(\.id)).count != nodes.count { throw GridValidationError("Node IDs must be unique.") }
    if ([base] + breakpoints.map(\.layout)).contains(where: { $0.flowGap != nil }),
      nodes.contains(where: { node in
        if case .builtin(let n) = node { return n.kind == .text && n.ignoreFlow != true && n.fitToBox == true }
        return false
      })
    {
      throw GridValidationError("Content-sized text cannot also fit a fixed-height box.")
    }
    var result = GridDocument(layout: base, breakpoints: breakpoints, nodes: nodes)
    if let raw = o["baseLayoutName"] {
      let name = try text(raw, 80, "Base layout name")
      if !jsTrim(name).isEmpty { result.baseLayoutName = name }
    }
    if let raw = o["baseLayoutIndex"] {
      result.baseLayoutIndex = min(try integer(raw, 0, 12, "Base layout position"), breakpoints.count)
    }
    if result.jsonString.utf8.count > GridLimits.maxDocumentBytes {
      throw GridValidationError("Grid content exceeds 180 KB.")
    }
    return result
  }

  // MARK: Layout

  static func layout(_ value: JSONValue?) throws -> GridLayoutSettings {
    let o = try object(value)
    if o["flowGap"] != nil, o["direction"] != .string("vertical") {
      throw GridValidationError("Content flow requires a vertical layout.")
    }
    let flowGap = try o["flowGap"].map { try integer($0, 0, 128, "Flow spacing") }
    let appearance = try appearance(o)
    let previewWidth = try o["previewWidth"].map { try integer($0, 240, 7680, "Preview width") }
    let previewHeight = try o["previewHeight"].map { try integer($0, 240, 7680, "Preview height") }
    let background = try o["background"].map(color)
    let color = try o["color"].map(color)
    let radius = try o["radius"].map { try integer($0, 0, 256, "Radius") }
    let direction: GridDirection = try choice(o["direction"])
    let columns = try integer(o["columns"], 1, 64, "Columns")
    let rows = try integer(o["rows"], 1, 64, "Rows")
    let cellSize = try integer(o["cellSize"], 8, 256, "Cell size")
    let gap = try integer(o["gap"], 0, 64, "Gap")
    let maxRows = try o["maxRows"].map { try integer($0, 1, 512, "Row limit") }
    let maxColumns = try o["maxColumns"].map { try integer($0, 1, 512, "Column limit") }
    return GridLayoutSettings(
      direction: direction, columns: columns, rows: rows, cellSize: cellSize, gap: gap, flowGap: flowGap,
      appearance: appearance, previewWidth: previewWidth, previewHeight: previewHeight, background: background,
      color: color, radius: radius, maxRows: maxRows, maxColumns: maxColumns)
  }

  static func appearance(_ o: JSONValue?) throws -> GridAppearance {
    var result = GridAppearance()
    if let raw = o?["backgroundImageId"] { result.backgroundImageId = raw == .null ? .some(nil) : try gridId(raw) }
    if let raw = o?["backgroundFit"] { result.backgroundFit = try choice(raw) as GridFit }
    if let raw = o?["padding"] { result.padding = try integer(raw, 0, 128, "Padding") }
    if let raw = o?["colorOpacity"] { result.colorOpacity = try number(raw, 0, 1) }
    if let raw = o?["backgroundOpacity"] { result.backgroundOpacity = try number(raw, 0, 1) }
    return result
  }

  static func frame(_ value: JSONValue?) throws -> GridFrame {
    let o = try object(value)
    return GridFrame(
      x: try integer(o["x"], 0, 511, "X"), y: try integer(o["y"], 0, 511, "Y"),
      width: try integer(o["width"], 1, 512, "Width"), height: try integer(o["height"], 1, 512, "Height"))
  }

  // MARK: Nodes

  static func node(_ value: JSONValue, breakpointIds: Set<String>) throws -> GridNode {
    let n = try object(value)
    guard case .object(let rawFrames)? = n["frames"] else { throw GridValidationError("Expected an object.") }
    if rawFrames.keys.contains(where: { !breakpointIds.contains($0) }) {
      throw GridValidationError("Unknown breakpoint frame.")
    }
    guard case .bool(let hidden)? = n["hidden"] else { throw GridValidationError("Invalid visibility.") }
    var ignoreFlow: Bool?
    if let raw = n["ignoreFlow"] {
      guard case .bool(let flag) = raw else { throw GridValidationError("Invalid stacking option.") }
      ignoreFlow = flag
    }
    if n["kind"] == .string("custom") {
      let nodeKey = jsTrim(try text(n["nodeKey"], 128, "Node key"))
      if nodeKey.isEmpty { throw GridValidationError("Enter a node key.") }
      guard case .array(let rawProperties)? = n["properties"], rawProperties.count <= 64 else {
        throw GridValidationError("Use up to 64 custom properties.")
      }
      let properties = try rawProperties.map { value -> GridCustomNode.Property in
        let pair = try object(value)
        // Self.: a later local named `text` in this function hides the helper for Swift 6.0/6.1.
        let key = jsTrim(try Self.text(pair["key"], 128, "Property key"))
        if key.isEmpty { throw GridValidationError("Enter a property key.") }
        return .init(key: key, value: try Self.text(pair["value"], 4000, "Property value"))
      }
      if Set(properties.map(\.key)).count != properties.count {
        throw GridValidationError("Property keys must be unique.")
      }
      let id = try gridId(n["id"])
      let name = try text(n["name"], GridLimits.nodeNameLimit, "Node name")
      let frame = try frame(n["frame"])
      let frames = try rawFrames.pairs.map { (id: $0.0, frame: try self.frame($0.1)) }
      let opacityValue = n["opacity"].flatMap { $0 == .null ? nil : $0 } ?? .number(0.5)
      return .custom(GridCustomNode(
        id: id, name: name, frame: frame, frames: frames, hidden: hidden, opacity: try number(opacityValue, 0, 1),
        nodeKey: nodeKey, properties: properties, ignoreFlow: ignoreFlow))
    }
    // nodeOptions(n), in grid-core's key order.
    let appearance = try appearance(n)
    var options: (dropcap: Bool?, fitToBox: Bool?, ignoreFlow: Bool?) = (nil, nil, nil)
    for key in ["dropcap", "fitToBox", "ignoreFlow"] {
      guard let raw = n[key] else { continue }
      guard case .bool(let flag) = raw else { throw GridValidationError("Invalid text option.") }
      switch key {
      case "dropcap": options.dropcap = flag
      case "fitToBox": options.fitToBox = flag
      default: options.ignoreFlow = flag
      }
    }
    let opacity = try n["opacity"].map { try number($0, 0, 1) }
    let borderOpacity = try n["borderOpacity"].map { try number($0, 0, 1) }
    let strokeOpacity = try n["strokeOpacity"].map { try number($0, 0, 1) }
    let borderColor = try n["borderColor"].map(color)
    let strokeColor = try n["strokeColor"].map(color)
    let borderWidth = try n["borderWidth"].map { try integer($0, 0, 64, "borderWidth") }
    let strokeWidth = try n["strokeWidth"].map { try integer($0, 0, 64, "strokeWidth") }
    let borderStyle = try n["borderStyle"].map { try choice($0) as GridBorderStyle }
    let strokeStyle = try n["strokeStyle"].map { try choice($0) as GridStrokeStyle }
    let link = try n["link"].map(gridLink)
    let url = try n["url"].map(gridLink)
    let rotation = try n["rotation"].map { try number($0, -360, 360) }
    let lineHeight = try n["lineHeight"].map { try number($0, 0.5, 4) }
    let fontAssetId: String?? = try n["fontAssetId"].map { $0 == .null ? nil : try gridId($0) }
    let fontFamily = try n["fontFamily"].map { try choice($0) as GridFontFamily }
    let verticalAlign = try n["verticalAlign"].map { try choice($0) as GridVerticalAlign }
    let iconName = try n["iconName"].map(gridId)
    let polygonSides = try n["polygonSides"].map { try integer($0, 3, 12, "Polygon sides") }
    let separatorStyle: GridSeparatorStyle? =
      n["kind"] == .string("separator")
      ? try choice(n["separatorStyle"].flatMap { $0 == .null ? nil : $0 } ?? .string("empty")) : nil
    let id = try gridId(n["id"])
    let kind: GridBuiltinKind = try choice(n["kind"])
    let name = try text(n["name"], GridLimits.nodeNameLimit, "Node name")
    let text = try text(n["text"], 16000, "Text")
    let assetId: String? = n["assetId"] == .null ? nil : try gridId(n["assetId"])
    let frame = try frame(n["frame"])
    let frames = try rawFrames.pairs.map { (id: $0.0, frame: try self.frame($0.1)) }
    var node = GridBuiltinNode(
      id: id, kind: kind, name: name, text: text, assetId: assetId, frame: frame, frames: frames,
      color: try color(n["color"]), background: try color(n["background"]),
      fontSize: try integer(n["fontSize"], 8, 256, "Font size"), radius: try integer(n["radius"], 0, 256, "Radius"),
      align: try choice(n["align"]), fit: try choice(n["fit"]), shape: try choice(n["shape"]), hidden: hidden)
    node.appearance = appearance
    node.dropcap = options.dropcap
    node.fitToBox = options.fitToBox
    node.ignoreFlow = options.ignoreFlow
    node.opacity = opacity
    node.borderOpacity = borderOpacity
    node.strokeOpacity = strokeOpacity
    node.borderColor = borderColor
    node.strokeColor = strokeColor
    node.borderWidth = borderWidth
    node.strokeWidth = strokeWidth
    node.borderStyle = borderStyle
    node.strokeStyle = strokeStyle
    node.link = link
    node.url = url
    node.rotation = rotation
    node.lineHeight = lineHeight
    node.fontAssetId = fontAssetId
    node.fontFamily = fontFamily
    node.verticalAlign = verticalAlign
    node.iconName = iconName
    node.polygonSides = polygonSides
    node.separatorStyle = separatorStyle
    return .builtin(node)
  }

  // MARK: Primitive checks

  static func object(_ value: JSONValue?) throws -> JSONValue {
    guard case .object? = value else { throw GridValidationError("Expected an object.") }
    return value!
  }

  static func integer(_ value: JSONValue?, _ min: Int, _ max: Int, _ field: String) throws -> Int {
    if case .number(let number)? = value, number.isFinite, number.rounded() == number,
      abs(number) <= 9_007_199_254_740_991, number >= Double(min), number <= Double(max)
    {
      return Int(number)
    }
    throw GridValidationError("\(field) must be between \(min) and \(max).")
  }

  static func number(_ value: JSONValue?, _ min: Double, _ max: Double) throws -> Double {
    if case .number(let number)? = value, number.isFinite, number >= min, number <= max { return number }
    throw GridValidationError("Invalid numeric option.")
  }

  static func text(_ value: JSONValue?, _ max: Int, _ field: String) throws -> String {
    if case .string(let string)? = value, string.utf16.count <= max { return string }
    throw GridValidationError("\(field) is too long or missing.")
  }

  static func choice<T: RawRepresentable>(_ value: JSONValue?) throws -> T where T.RawValue == String {
    if case .string(let string)? = value, let result = T(rawValue: string) { return result }
    throw GridValidationError("Invalid option.")
  }

  static func color(_ value: JSONValue?) throws -> GridColor {
    if case .string(let string)? = value, let color = GridColor(string) { return color }
    throw GridValidationError("Use a six-digit color or transparent.")
  }

  /// `gridId`: 1–128 ASCII letters, digits, `_` or `-`.
  public static func gridId(_ value: JSONValue?) throws -> String {
    if case .string(let string)? = value, isGridId(string) { return string }
    throw GridValidationError("Invalid identifier.")
  }

  public static func isGridId(_ string: String) -> Bool {
    let bytes = string.utf8
    return (1...128).contains(bytes.count) && bytes.allSatisfy { byte in
      (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
        || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
    }
  }

  /// `gridLink`: an empty string, or a credential-free http(s) URL normalized like WHATWG `URL.href`.
  static func gridLink(_ value: JSONValue) throws -> String {
    if value == .string("") { return "" }
    let raw = try text(value, 2048, "URL")
    if let href = GridURL.safeHref(raw) { return href }
    throw GridValidationError("Use an http or https URL.")
  }
}

/// JavaScript `String.prototype.trim`: WhiteSpace and LineTerminator code points.
public func jsTrim(_ value: String) -> String {
  func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
      0x3000, 0xFEFF:
      return true
    default:
      return false
    }
  }
  let scalars = value.unicodeScalars
  guard let start = scalars.firstIndex(where: { !isSpace($0) }) else { return "" }
  let end = scalars.lastIndex(where: { !isSpace($0) })!
  return String(scalars[start...end])
}
