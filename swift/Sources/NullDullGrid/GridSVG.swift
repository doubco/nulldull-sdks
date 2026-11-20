import Foundation

/// A parsed SVG element that passed the static-drawing allowlist.
public struct GridSVGElement: Hashable, Sendable {
  public var name: String
  public var attributes: [String: String]
  public var children: [GridSVGElement]
}

/// Static SVG support: a port of grid-core's `isSafeGridSvg` allowlist plus a parser
/// that turns accepted markup into an element tree. Scripts, styles, external
/// references, entities and anything outside the allowlist reject the whole file.
public enum GridSVG {
  /// Same check as `isSafeGridSvg`.
  public static func isSafe(_ source: String) -> Bool { parse(source) != nil }

  /// Parses a safe SVG, or returns nil for anything `isSafeGridSvg` rejects.
  public static func parse(_ input: String) -> GridSVGElement? {
    guard input.utf16.count <= GridLimits.svgMaxBytes else { return nil }
    var source = jsTrim(input) as NSString
    if let declaration = regex(
      #"^<\?xml\s+version=["']1\.0["'](?:\s+encoding=["']UTF-8["'])?(?:\s+standalone=["'](?:yes|no)["'])?\s*\?>"#,
      caseInsensitive: true
    ).firstMatch(in: source as String, range: NSRange(location: 0, length: source.length)) {
      source = source.replacingCharacters(in: declaration.range, with: "") as NSString
    }
    // Remove comments; an unterminated comment rejects.
    var pieces: [String] = []
    var cursor = 0
    var comments = 0
    while true {
      let start = source.range(of: "<!--", range: NSRange(location: cursor, length: source.length - cursor))
      if start.location == NSNotFound { break }
      comments += 1
      if comments > 10000 { return nil }
      let searchFrom = start.location + 4
      let end = source.range(of: "-->", range: NSRange(location: searchFrom, length: source.length - searchFrom))
      if end.location == NSNotFound { return nil }
      pieces.append(source.substring(with: NSRange(location: cursor, length: start.location - cursor)))
      cursor = end.location + 3
    }
    pieces.append(source.substring(from: cursor))
    let text = pieces.joined() as NSString
    let whole = NSRange(location: 0, length: text.length)
    if text.length == 0 || text.length > 10 * 1024 * 1024
      || regex(#"<!|<\?|&|[\u0000-\u0008]"#).firstMatch(in: text as String, range: whole) != nil
    {
      return nil
    }

    var stack: [GridSVGElement] = []
    var root: GridSVGElement?
    var position = 0
    var roots = 0
    var tagCount = 0
    let tagPattern = regex(#"<(/?)([A-Za-z]+)\b([^<>]*)>"#)
    let attributePattern = regex(#"\s+([A-Za-z0-9_:-]+)\s*=\s*(["'])(.*?)\2"#)
    for match in tagPattern.matches(in: text as String, range: whole) {
      tagCount += 1
      if tagCount > 10000 || stack.count > 64 { return nil }
      let between = text.substring(with: NSRange(location: position, length: match.range.location - position))
      if between.contains("<") || between.contains(">") || (stack.isEmpty && !jsTrim(between).isEmpty) {
        return nil
      }
      let close = match.range(at: 1).length > 0
      let tag = text.substring(with: match.range(at: 2))
      let body = text.substring(with: match.range(at: 3))
      let trimmed = body.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
      let selfClosing = trimmed.hasSuffix("/")
      let attrs = (selfClosing ? String(trimmed.dropLast()) : trimmed) as NSString
      guard tags.contains(tag) else { return nil }
      if close {
        guard jsTrim(attrs as String).isEmpty, !selfClosing, let element = stack.popLast(), element.name == tag else {
          return nil
        }
        if stack.isEmpty { root = element } else { stack[stack.count - 1].children.append(element) }
      } else {
        if stack.isEmpty {
          roots += 1
          if tag != "svg" || roots != 1 { return nil }
        }
        var attributeEnd = 0
        var attributes: [String: String] = [:]
        while attributeEnd < attrs.length,
          !jsTrim(attrs.substring(from: attributeEnd)).isEmpty
        {
          guard
            let attribute = attributePattern.firstMatch(
              in: attrs as String, options: .anchored, range: NSRange(location: attributeEnd, length: attrs.length - attributeEnd))
          else { return nil }
          let name = attrs.substring(with: attribute.range(at: 1))
          let value = attrs.substring(with: attribute.range(at: 3))
          if attributes.count >= 64 || attributes[name] != nil { return nil }
          attributes[name] = value
          attributeEnd = attribute.range.location + attribute.range.length
          guard attributeNames.contains(name) else { return nil }
          if name == "xmlns" && value != "http://www.w3.org/2000/svg" { return nil }
          if name == "xmlns:xlink" && value != "http://www.w3.org/1999/xlink" { return nil }
          if name == "xml:space" && !["default", "preserve"].contains(value) { return nil }
          if name == "version" && !["1.0", "1.1", "2.0"].contains(value) { return nil }
          if name == "overflow" && !["visible", "hidden", "auto", "scroll"].contains(value) { return nil }
          if name == "style" && !isStaticStyle(value) { return nil }
          if name != "xmlns" && name != "xmlns:xlink",
            regex(#"[<>\\]|(?:https?:|data:|javascript:)"#, caseInsensitive: true).firstMatch(
              in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil
          {
            return nil
          }
          if name != "style", value.range(of: #"url\s*\("#, options: [.regularExpression, .caseInsensitive]) != nil,
            !isFragmentURL(value)
          {
            return nil
          }
        }
        if !jsTrim(attrs.substring(from: min(attributeEnd, attrs.length))).isEmpty { return nil }
        let element = GridSVGElement(name: tag, attributes: attributes, children: [])
        if selfClosing {
          if stack.isEmpty { root = element } else { stack[stack.count - 1].children.append(element) }
        } else {
          stack.append(element)
        }
      }
      position = match.range.location + match.range.length
    }
    guard roots == 1, stack.isEmpty, jsTrim(text.substring(from: position)).isEmpty else { return nil }
    return root
  }

  static let tags: Set<String> = [
    "svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "defs", "clipPath", "mask",
    "linearGradient", "radialGradient", "stop", "title", "desc",
  ]

  static let attributeNames: Set<String> = Set(
    "xmlns xmlns:xlink version xml:space enable-background overflow style viewBox width height x y x1 x2 y1 y2 cx cy r rx ry d points fill fill-rule fill-opacity stroke stroke-width stroke-linecap stroke-linejoin stroke-dasharray stroke-dashoffset stroke-opacity opacity transform id clip-path mask gradientUnits gradientTransform offset stop-color stop-opacity spreadMethod fx fy preserveAspectRatio"
      .split(separator: " ").map(String.init))

  static let styleProperties: Set<String> = Set(
    "fill fill-opacity fill-rule stroke stroke-width stroke-linecap stroke-linejoin stroke-dasharray stroke-dashoffset stroke-opacity stroke-miterlimit stop-color stop-opacity opacity display visibility clip-rule color"
      .split(separator: " ").map(String.init))

  static func isFragmentURL(_ value: String) -> Bool {
    value.range(of: #"^url\(#[A-Za-z][A-Za-z0-9_-]*\)$"#, options: .regularExpression) != nil
  }

  /// Inline styles may only paint: allowlisted properties with plain values or fragment `url()`.
  static func isStaticStyle(_ value: String) -> Bool {
    let declarations = value.components(separatedBy: ";")
    if declarations.count > 64 { return false }
    for declaration in declarations where !jsTrim(declaration).isEmpty {
      guard let colon = declaration.firstIndex(of: ":"),
        styleProperties.contains(jsTrim(String(declaration[..<colon])))
      else { return false }
      var css = jsTrim(String(declaration[declaration.index(after: colon)...]))
      if css.lowercased().hasSuffix("!important") { css = jsTrim(String(css.dropLast(10))) }
      if isFragmentURL(css) { continue }
      let plain = css.replacingOccurrences(
        of: #"\b(?:rgba?|hsla?|color)\(\s*[-A-Za-z0-9_\s.,%/]*\)"#, with: "",
        options: [.regularExpression, .caseInsensitive])
      if plain.range(of: #"^[-#A-Za-z0-9_\s.,%]*$"#, options: .regularExpression) == nil { return false }
    }
    return true
  }

  static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
    // Patterns are literals; a failure is a programming error.
    try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
  }
}

// MARK: - Drawing model

/// A path in SVG user units. Arcs and quadratic curves are converted to cubic Béziers.
public enum GridPathCommand: Hashable, Sendable {
  case move(Double, Double)
  case line(Double, Double)
  case cubic(Double, Double, Double, Double, Double, Double)
  case close
}

public struct GridAffineTransform: Hashable, Sendable {
  public var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0
  public static let identity = GridAffineTransform()
  public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
    (self.a, self.b, self.c, self.d, self.tx, self.ty) = (a, b, c, d, tx, ty)
  }
  /// self applied after `other` (other first).
  public func concatenating(_ next: GridAffineTransform) -> GridAffineTransform {
    GridAffineTransform(
      a: a * next.a + b * next.c, b: a * next.b + b * next.d,
      c: c * next.a + d * next.c, d: c * next.b + d * next.d,
      tx: tx * next.a + ty * next.c + next.tx, ty: tx * next.b + ty * next.d + next.ty)
  }
}

public struct GridRGBA: Hashable, Sendable {
  public var red: Double, green: Double, blue: Double, alpha: Double
}

/// A resolved fill or stroke.
public enum GridSVGPaint: Hashable, Sendable {
  case color(GridRGBA)
  /// `currentColor`: the host's text colour for inline icons; black for SVG files shown as images.
  case currentColor(opacity: Double)
}

/// One filled and/or stroked shape, in paint order, with inherited presentation resolved.
public struct GridSVGShape: Hashable, Sendable {
  public var commands: [GridPathCommand]
  /// Maps SVG user units into the root viewBox space.
  public var transform: GridAffineTransform
  public var fill: GridSVGPaint?
  public var evenOdd: Bool
  public var stroke: GridSVGPaint?
  public var strokeWidth: Double
  public var lineCap: String
  public var lineJoin: String
  public var miterLimit: Double
  public var dash: [Double]
  public var dashOffset: Double
}

public struct GridSVGDrawing: Hashable, Sendable {
  /// The viewBox (or the width/height box when there is none).
  public var viewBox: (x: Double, y: Double, width: Double, height: Double)
  /// Intrinsic size, for `object-fit: contain`.
  public var intrinsicWidth: Double
  public var intrinsicHeight: Double
  /// `preserveAspectRatio`: nil alignment means `none`.
  public var align: (x: Double, y: Double)?
  public var slice: Bool
  public var shapes: [GridSVGShape]

  public static func == (a: GridSVGDrawing, b: GridSVGDrawing) -> Bool {
    a.shapes == b.shapes && a.intrinsicWidth == b.intrinsicWidth && a.intrinsicHeight == b.intrinsicHeight
  }
  public func hash(into hasher: inout Hasher) { hasher.combine(shapes) }
}

public enum GridSVGRenderError: Error, Equatable, Sendable {
  /// The SVG failed the static allowlist.
  case unsafe
  /// Safe, but uses a feature the native renderer does not draw (gradients, clipping, masks,
  /// percentages, unknown colour names). The renderer shows its fallback instead of guessing.
  case unsupported(String)
}

extension GridSVG {
  /// Resolves a safe SVG into drawable shapes.
  public static func drawing(_ source: String) throws -> GridSVGDrawing {
    guard let root = parse(source) else { throw GridSVGRenderError.unsafe }
    let width = try length(root.attributes["width"])
    let height = try length(root.attributes["height"])
    var box: (x: Double, y: Double, width: Double, height: Double)
    if let viewBox = root.attributes["viewBox"] {
      let numbers = try numberList(viewBox)
      guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { throw GridSVGRenderError.unsupported("viewBox") }
      box = (numbers[0], numbers[1], numbers[2], numbers[3])
    } else {
      box = (0, 0, width ?? 300, height ?? 150)
    }
    let intrinsicWidth = width ?? (height.map { $0 * box.width / box.height } ?? box.width)
    let intrinsicHeight = height ?? (width.map { $0 * box.height / box.width } ?? box.height)
    var align: (Double, Double)? = (0.5, 0.5)
    var slice = false
    if let value = root.attributes["preserveAspectRatio"] {
      let parts = value.split(separator: " ").map(String.init)
      switch parts.first ?? "" {
      case "none": align = nil
      case let key:
        let xs = ["xMin": 0.0, "xMid": 0.5, "xMax": 1.0]
        let ys = ["YMin": 0.0, "YMid": 0.5, "YMax": 1.0]
        guard key.count == 8, let x = xs[String(key.prefix(4))], let y = ys[String(key.suffix(4))] else {
          throw GridSVGRenderError.unsupported("preserveAspectRatio")
        }
        align = (x, y)
      }
      slice = parts.count > 1 && parts[1] == "slice"
    }
    var shapes: [GridSVGShape] = []
    try collect(root, style: Presentation(), transform: .identity, into: &shapes)
    return GridSVGDrawing(
      viewBox: box, intrinsicWidth: intrinsicWidth, intrinsicHeight: intrinsicHeight, align: align, slice: slice,
      shapes: shapes)
  }

  struct Presentation {
    var fill: String = "black"
    var fillOpacity = 1.0
    var fillRule = "nonzero"
    var stroke: String = "none"
    var strokeOpacity = 1.0
    var strokeWidth = 1.0
    var lineCap = "butt"
    var lineJoin = "miter"
    var miterLimit = 4.0
    var dash: [Double] = []
    var dashOffset = 0.0
    var color = "currentColor"
    var opacity = 1.0
    var groupAlpha = 1.0
    var visible = true
  }

  static func collect(
    _ element: GridSVGElement, style inherited: Presentation, transform parent: GridAffineTransform,
    into shapes: inout [GridSVGShape]
  ) throws {
    switch element.name {
    case "defs", "title", "desc", "linearGradient", "radialGradient", "stop", "clipPath", "mask": return
    default: break
    }
    if element.attributes["clip-path"] != nil || element.attributes["mask"] != nil {
      throw GridSVGRenderError.unsupported("clip-path/mask")
    }
    var style = inherited
    style.opacity = 1
    var declarations: [(String, String)] = element.attributes.compactMap { key, value in
      Presentation.keys.contains(key) ? (key, value) : nil
    }
    if let inline = element.attributes["style"] {
      for declaration in inline.split(separator: ";") {
        guard let colon = declaration.firstIndex(of: ":") else { continue }
        var value = jsTrim(String(declaration[declaration.index(after: colon)...]))
        if value.lowercased().hasSuffix("!important") { value = jsTrim(String(value.dropLast(10))) }
        declarations.append((jsTrim(String(declaration[..<colon])), value))
      }
    }
    for (key, value) in declarations {
      switch key {
      case "fill": style.fill = value
      case "fill-opacity": style.fillOpacity = try opacity(value)
      case "fill-rule": style.fillRule = value
      case "stroke": style.stroke = value
      case "stroke-opacity": style.strokeOpacity = try opacity(value)
      case "stroke-width": style.strokeWidth = try length(value) ?? 1
      case "stroke-linecap": style.lineCap = value
      case "stroke-linejoin": style.lineJoin = value
      case "stroke-miterlimit": style.miterLimit = Double(value) ?? 4
      case "stroke-dasharray": style.dash = value == "none" ? [] : try numberList(value)
      case "stroke-dashoffset": style.dashOffset = try length(value) ?? 0
      case "color": style.color = value
      case "opacity": style.opacity = try opacity(value)
      case "display": if value == "none" { return }
      case "visibility": style.visible = value == "visible" || value == "inherit"
      default: break
      }
    }
    // Group opacity is approximated by multiplying it into each descendant's paint alpha.
    style.groupAlpha *= style.opacity
    var transform = parent
    if let value = element.attributes["transform"] { transform = try parseTransform(value).concatenating(parent) }
    let commands: [GridPathCommand]?
    let a = element.attributes
    func num(_ key: String) throws -> Double { try length(a[key]) ?? 0 }
    switch element.name {
    case "svg", "g":
      for child in element.children { try collect(child, style: style, transform: transform, into: &shapes) }
      return
    case "path": commands = try pathCommands(a["d"] ?? "")
    case "rect":
      let (x, y, w, h) = (try num("x"), try num("y"), try num("width"), try num("height"))
      guard w > 0, h > 0 else { return }
      var rx = try length(a["rx"])
      var ry = try length(a["ry"])
      if rx == nil { rx = ry }
      if ry == nil { ry = rx }
      commands = roundedRect(x, y, w, h, min(rx ?? 0, w / 2), min(ry ?? 0, h / 2))
    case "circle":
      let r = try num("r")
      guard r > 0 else { return }
      commands = ellipse(try num("cx"), try num("cy"), r, r)
    case "ellipse":
      let (rx, ry) = (try num("rx"), try num("ry"))
      guard rx > 0, ry > 0 else { return }
      commands = ellipse(try num("cx"), try num("cy"), rx, ry)
    case "line":
      commands = [.move(try num("x1"), try num("y1")), .line(try num("x2"), try num("y2"))]
    case "polyline", "polygon":
      let points = try numberList(a["points"] ?? "")
      guard points.count >= 2 else { return }
      var list: [GridPathCommand] = [.move(points[0], points[1])]
      var index = 2
      while index + 1 < points.count {
        list.append(.line(points[index], points[index + 1]))
        index += 2
      }
      if element.name == "polygon" { list.append(.close) }
      commands = list
    default:
      commands = nil
    }
    guard let commands, style.visible, !commands.isEmpty else { return }
    let fill = try paint(style.fill, opacity: style.fillOpacity * style.groupAlpha, currentColor: style.color)
    let stroke = try paint(style.stroke, opacity: style.strokeOpacity * style.groupAlpha, currentColor: style.color)
    shapes.append(GridSVGShape(
      commands: commands, transform: transform, fill: element.name == "line" ? nil : fill,
      evenOdd: style.fillRule == "evenodd", stroke: stroke, strokeWidth: style.strokeWidth, lineCap: style.lineCap,
      lineJoin: style.lineJoin, miterLimit: style.miterLimit, dash: style.dash, dashOffset: style.dashOffset))
  }

  static func opacity(_ value: String) throws -> Double {
    if value.hasSuffix("%"), let number = Double(value.dropLast()) { return max(0, min(1, number / 100)) }
    guard let number = Double(jsTrim(value)) else { throw GridSVGRenderError.unsupported("opacity \(value)") }
    return max(0, min(1, number))
  }

  /// Lengths in user units; `px` is accepted, percentages and other units are not drawn.
  static func length(_ value: String?) throws -> Double? {
    guard var text = value.map(jsTrim), !text.isEmpty else { return nil }
    if text.hasSuffix("px") { text.removeLast(2) }
    guard let number = Double(text), number.isFinite else { throw GridSVGRenderError.unsupported("length \(text)") }
    return number
  }

  static func numberList(_ value: String) throws -> [Double] {
    var scanner = NumberScanner(Array(value.utf8))
    var result: [Double] = []
    while let number = try scanner.next() { result.append(number) }
    return result
  }

  static func paint(_ value: String, opacity: Double, currentColor: String) throws -> GridSVGPaint? {
    let text = jsTrim(value)
    if text == "none" || text == "transparent" { return nil }
    if text.lowercased() == "currentcolor" {
      if currentColor.lowercased() == "currentcolor" { return .currentColor(opacity: opacity) }
      return try paint(currentColor, opacity: opacity, currentColor: "currentColor")
    }
    if text.hasPrefix("url(") { throw GridSVGRenderError.unsupported("paint server \(text)") }
    guard var color = cssColor(text) else { throw GridSVGRenderError.unsupported("colour \(text)") }
    color.alpha *= opacity
    return .color(color)
  }

  static func cssColor(_ input: String) -> GridRGBA? {
    let text = input.lowercased()
    if text.hasPrefix("#") {
      let hex = Array(text.dropFirst())
      guard hex.allSatisfy(\.isHexDigit) else { return nil }
      func value(_ digits: [Character]) -> Double { Double(Int(String(digits), radix: 16) ?? 0) / (digits.count == 1 ? 15 : 255) }
      switch hex.count {
      case 3, 4:
        return GridRGBA(red: value([hex[0]]), green: value([hex[1]]), blue: value([hex[2]]), alpha: hex.count == 4 ? value([hex[3]]) : 1)
      case 6, 8:
        return GridRGBA(
          red: value(Array(hex[0...1])), green: value(Array(hex[2...3])), blue: value(Array(hex[4...5])),
          alpha: hex.count == 8 ? value(Array(hex[6...7])) : 1)
      default: return nil
      }
    }
    if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
      let name = text[..<open]
      let args = text[text.index(after: open)..<text.index(before: text.endIndex)]
        .replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ",", with: " ")
        .split(separator: " ").map(String.init)
      func channel(_ value: String, scale: Double) -> Double? {
        if value.hasSuffix("%") { return Double(value.dropLast()).map { $0 / 100 } }
        return Double(value).map { $0 / scale }
      }
      guard args.count == 3 || args.count == 4 else { return nil }
      let alpha = args.count == 4 ? channel(args[3], scale: 1) : 1
      if name == "rgb" || name == "rgba" {
        guard let r = channel(args[0], scale: 255), let g = channel(args[1], scale: 255),
          let b = channel(args[2], scale: 255), let alpha
        else { return nil }
        return GridRGBA(red: r, green: g, blue: b, alpha: alpha)
      }
      if name == "hsl" || name == "hsla" {
        guard let h = Double(args[0].replacingOccurrences(of: "deg", with: "")), let s = channel(args[1], scale: 100),
          let l = channel(args[2], scale: 100), let alpha
        else { return nil }
        let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        func f(_ n: Double) -> Double {
          let k = (n + hue * 12).truncatingRemainder(dividingBy: 12)
          return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1))
        }
        return GridRGBA(red: f(0), green: f(8), blue: f(4), alpha: alpha)
      }
      return nil
    }
    guard let rgb = namedColors[text] else { return nil }
    return GridRGBA(
      red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255,
      alpha: 1)
  }

  /// CSS basic colours and the names design tools commonly write.
  static let namedColors: [String: Int] = [
    "black": 0x000000, "silver": 0xC0C0C0, "gray": 0x808080, "grey": 0x808080, "white": 0xFFFFFF,
    "maroon": 0x800000, "red": 0xFF0000, "purple": 0x800080, "fuchsia": 0xFF00FF, "magenta": 0xFF00FF,
    "green": 0x008000, "lime": 0x00FF00, "olive": 0x808000, "yellow": 0xFFFF00, "navy": 0x000080, "blue": 0x0000FF,
    "teal": 0x008080, "aqua": 0x00FFFF, "cyan": 0x00FFFF, "orange": 0xFFA500, "pink": 0xFFC0CB, "gold": 0xFFD700,
    "brown": 0xA52A2A, "darkgray": 0xA9A9A9, "darkgrey": 0xA9A9A9, "lightgray": 0xD3D3D3, "lightgrey": 0xD3D3D3,
    "dimgray": 0x696969, "dimgrey": 0x696969, "whitesmoke": 0xF5F5F5, "gainsboro": 0xDCDCDC,
  ]

  static func parseTransform(_ value: String) throws -> GridAffineTransform {
    var result = GridAffineTransform.identity
    let pattern = regex(#"([A-Za-z]+)\s*\(([^)]*)\)"#)
    let ns = value as NSString
    var consumed = 0
    for match in pattern.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
      let gapText = ns.substring(with: NSRange(location: consumed, length: match.range.location - consumed))
      guard gapText.allSatisfy({ $0.isWhitespace || $0 == "," }) else {
        throw GridSVGRenderError.unsupported("transform")
      }
      consumed = match.range.location + match.range.length
      let name = ns.substring(with: match.range(at: 1))
      let v = try numberList(ns.substring(with: match.range(at: 2)))
      let t: GridAffineTransform
      switch (name, v.count) {
      case ("matrix", 6): t = GridAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
      case ("translate", 1): t = GridAffineTransform(tx: v[0])
      case ("translate", 2): t = GridAffineTransform(tx: v[0], ty: v[1])
      case ("scale", 1): t = GridAffineTransform(a: v[0], d: v[0])
      case ("scale", 2): t = GridAffineTransform(a: v[0], d: v[1])
      case ("rotate", 1), ("rotate", 3):
        let r = v[0] * .pi / 180
        let rotation = GridAffineTransform(a: cos(r), b: sin(r), c: -sin(r), d: cos(r))
        if v.count == 3 {
          t = GridAffineTransform(tx: -v[1], ty: -v[2]).concatenating(rotation)
            .concatenating(GridAffineTransform(tx: v[1], ty: v[2]))
        } else {
          t = rotation
        }
      case ("skewX", 1): t = GridAffineTransform(c: tan(v[0] * .pi / 180))
      case ("skewY", 1): t = GridAffineTransform(b: tan(v[0] * .pi / 180))
      default: throw GridSVGRenderError.unsupported("transform \(name)")
      }
      // The list applies right to left: the last transform is closest to the shape.
      result = t.concatenating(result)
    }
    guard ns.substring(from: consumed).allSatisfy({ $0.isWhitespace || $0 == "," }) else {
      throw GridSVGRenderError.unsupported("transform")
    }
    return result
  }

  static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> [GridPathCommand] {
    let k = 0.5522847498307936
    return [
      .move(cx + rx, cy),
      .cubic(cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry),
      .cubic(cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy),
      .cubic(cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry),
      .cubic(cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy),
      .close,
    ]
  }

  static func roundedRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ rx: Double, _ ry: Double)
    -> [GridPathCommand]
  {
    guard rx > 0, ry > 0 else {
      return [.move(x, y), .line(x + w, y), .line(x + w, y + h), .line(x, y + h), .close]
    }
    let k = 0.5522847498307936
    return [
      .move(x + rx, y), .line(x + w - rx, y),
      .cubic(x + w - rx + rx * k, y, x + w, y + ry - ry * k, x + w, y + ry),
      .line(x + w, y + h - ry),
      .cubic(x + w, y + h - ry + ry * k, x + w - rx + rx * k, y + h, x + w - rx, y + h),
      .line(x + rx, y + h),
      .cubic(x + rx - rx * k, y + h, x, y + h - ry + ry * k, x, y + h - ry),
      .line(x, y + ry),
      .cubic(x, y + ry - ry * k, x + rx - rx * k, y, x + rx, y),
      .close,
    ]
  }

  /// Parses SVG path data (all commands, implicit repetition, compact arc flags).
  public static func pathCommands(_ data: String) throws -> [GridPathCommand] {
    var scanner = NumberScanner(Array(data.utf8))
    var result: [GridPathCommand] = []
    var current = (x: 0.0, y: 0.0), start = (x: 0.0, y: 0.0)
    var lastControl: (x: Double, y: Double)?
    var lastCommand: UInt8 = 0
    var lastQuad: (x: Double, y: Double)?
    while true {
      scanner.skipSeparators()
      guard let byte = scanner.peek() else { break }
      var command: UInt8
      if (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) {
        command = byte
        scanner.index += 1
      } else {
        guard lastCommand != 0, lastCommand != UInt8(ascii: "Z"), lastCommand != UInt8(ascii: "z") else {
          throw GridSVGRenderError.unsupported("path data")
        }
        command = lastCommand == UInt8(ascii: "M") ? UInt8(ascii: "L") : lastCommand == UInt8(ascii: "m") ? UInt8(ascii: "l") : lastCommand
      }
      let relative = (0x61...0x7A).contains(command)
      let upper = relative ? command - 32 : command
      func n() throws -> Double {
        guard let value = try scanner.next() else { throw GridSVGRenderError.unsupported("path data") }
        return value
      }
      func point() throws -> (x: Double, y: Double) {
        let x = try n(), y = try n()
        return relative ? (current.x + x, current.y + y) : (x, y)
      }
      var control: (x: Double, y: Double)?
      var quad: (x: Double, y: Double)?
      switch upper {
      case UInt8(ascii: "M"):
        current = try point()
        start = current
        result.append(.move(current.x, current.y))
      case UInt8(ascii: "L"):
        current = try point()
        result.append(.line(current.x, current.y))
      case UInt8(ascii: "H"):
        let x = try n()
        current.x = relative ? current.x + x : x
        result.append(.line(current.x, current.y))
      case UInt8(ascii: "V"):
        let y = try n()
        current.y = relative ? current.y + y : y
        result.append(.line(current.x, current.y))
      case UInt8(ascii: "C"):
        let c1 = try point(), c2 = try point(), end = try point()
        result.append(.cubic(c1.x, c1.y, c2.x, c2.y, end.x, end.y))
        control = c2
        current = end
      case UInt8(ascii: "S"):
        let c1 = lastControl.map { (2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
        let c2 = try point(), end = try point()
        result.append(.cubic(c1.0, c1.1, c2.x, c2.y, end.x, end.y))
        control = c2
        current = end
      case UInt8(ascii: "Q"):
        let q = try point(), end = try point()
        result.append(quadratic(current, q, end))
        quad = q
        current = end
      case UInt8(ascii: "T"):
        let q = lastQuad.map { (x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
        let end = try point()
        result.append(quadratic(current, q, end))
        quad = q
        current = end
      case UInt8(ascii: "A"):
        let rx = try n(), ry = try n(), rotation = try n()
        let large = try scanner.flag(), sweep = try scanner.flag()
        let end = try point()
        result.append(contentsOf: arc(from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep))
        current = end
      case UInt8(ascii: "Z"):
        result.append(.close)
        current = start
      default:
        throw GridSVGRenderError.unsupported("path command")
      }
      lastControl = control
      lastQuad = quad
      lastCommand = command
    }
    return result
  }

  static func quadratic(_ p0: (x: Double, y: Double), _ q: (x: Double, y: Double), _ p: (x: Double, y: Double))
    -> GridPathCommand
  {
    .cubic(
      p0.x + 2 / 3 * (q.x - p0.x), p0.y + 2 / 3 * (q.y - p0.y), p.x + 2 / 3 * (q.x - p.x), p.y + 2 / 3 * (q.y - p.y),
      p.x, p.y)
  }

  /// Endpoint arc to cubic Béziers (SVG 1.1 implementation notes F.6).
  static func arc(
    from p0: (x: Double, y: Double), to p: (x: Double, y: Double), rx rxIn: Double, ry ryIn: Double,
    rotation: Double, large: Bool, sweep: Bool
  ) -> [GridPathCommand] {
    var rx = abs(rxIn), ry = abs(ryIn)
    if rx == 0 || ry == 0 || (p0.x == p.x && p0.y == p.y) { return [.line(p.x, p.y)] }
    let phi = rotation * .pi / 180
    let (cosPhi, sinPhi) = (cos(phi), sin(phi))
    let dx = (p0.x - p.x) / 2, dy = (p0.y - p.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var factor = sqrt(max(0, numerator / denominator))
    if large == sweep { factor = -factor }
    let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
    let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p.x) / 2
    let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p.y) / 2
    func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
      let sign: Double = ux * vy - uy * vx < 0 ? -1 : 1
      let dot = (ux * vx + uy * vy) / (sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy))
      return sign * acos(max(-1, min(1, dot)))
    }
    let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if !sweep && delta > 0 { delta -= 2 * .pi }
    if sweep && delta < 0 { delta += 2 * .pi }
    let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
    let step = delta / Double(segments)
    let t = 4 / 3 * tan(step / 4)
    var result: [GridPathCommand] = []
    var theta = theta1
    func pointAt(_ angle: Double) -> (Double, Double) {
      let x = rx * cos(angle), y = ry * sin(angle)
      return (cosPhi * x - sinPhi * y + cx, sinPhi * x + cosPhi * y + cy)
    }
    func derivative(_ angle: Double) -> (Double, Double) {
      let x = -rx * sin(angle), y = ry * cos(angle)
      return (cosPhi * x - sinPhi * y, sinPhi * x + cosPhi * y)
    }
    for index in 0..<segments {
      let next = theta + step
      let a = pointAt(theta), b = pointAt(next)
      let da = derivative(theta), db = derivative(next)
      let end = index == segments - 1 ? (p.x, p.y) : b
      result.append(.cubic(a.0 + t * da.0, a.1 + t * da.1, b.0 - t * db.0, b.1 - t * db.1, end.0, end.1))
      theta = next
    }
    return result
  }
}

extension GridSVG.Presentation {
  static let keys: Set<String> = [
    "fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity", "stroke-width", "stroke-linecap",
    "stroke-linejoin", "stroke-dasharray", "stroke-dashoffset", "opacity",
  ]
}

struct NumberScanner {
  let bytes: [UInt8]
  var index = 0
  init(_ bytes: [UInt8]) { self.bytes = bytes }

  func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }

  mutating func skipSeparators() {
    while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D, 0x0C, UInt8(ascii: ",")].contains(bytes[index]) { index += 1 }
  }

  mutating func flag() throws -> Bool {
    skipSeparators()
    guard let byte = peek(), byte == UInt8(ascii: "0") || byte == UInt8(ascii: "1") else {
      throw GridSVGRenderError.unsupported("arc flag")
    }
    index += 1
    return byte == UInt8(ascii: "1")
  }

  /// The next number, or nil at the end or before a command letter.
  mutating func next() throws -> Double? {
    skipSeparators()
    let start = index
    func digits() -> Int {
      let from = index
      while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
      return index - from
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
    var count = digits()
    if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
      index += 1
      count += digits()
    }
    if count == 0 {
      index = start
      if let byte = peek(), !((0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)) {
        throw GridSVGRenderError.unsupported("number")
      }
      return nil
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
      let mark = index
      index += 1
      if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
      if digits() == 0 { index = mark }
    }
    guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
      throw GridSVGRenderError.unsupported("number")
    }
    return value
  }
}
