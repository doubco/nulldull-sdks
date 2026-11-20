import Foundation
import NullDullGrid
import SwiftUI

/// Built-in shapes, drawn like the web renderer's 100×100 SVG viewBox.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridShapeView: View {
  let node: GridBuiltinNode
  let foreground: Color
  let assetURL: URL?
  let messages: GridMessages
  /// The surface's content size.
  let size: CGSize

  var body: some View {
    let fill = themeColor(node.color, foreground)
    let stroke = withOpacity(themeColor(node.strokeColor, foreground), node.strokeOpacity)
    let padding = CGFloat(node.appearance.padding ?? 0)
    switch node.shape {
    case .svg:
      if let assetURL {
        GridSVGAssetView(url: assetURL, name: node.name, messages: messages)
          .frame(width: size.width, height: size.height)
          // The web renderer pads the <img> without border-box sizing, so the image keeps
          // the full box size and shifts by the padding; the surface clips the overflow.
          .offset(x: padding, y: padding)
      } else {
        GridPlaceholder(text: messages.chooseAsset)
      }
    case .icon:
      let source = GridIconCatalog.svg[node.iconName ?? ""] ?? GridIconCatalog.svg["grid-shape"]!
      GridSVGView(drawing: try? GridSVG.drawing(source), currentColor: fill, fitViewBoxOnly: true)
        .opacity(node.appearance.colorOpacity ?? 1)
        .frame(width: size.width, height: size.height)
        .offset(x: padding, y: padding)
        .accessibilityHidden(true)
    case .rectangle:
      // Border-box padding: the rectangle is inset by the padding.
      let radius = CGFloat(node.radius)
      let width = CGFloat(node.strokeWidth ?? 0)
      RoundedRectangle(cornerRadius: radius)
        .fill(withOpacity(fill, node.appearance.colorOpacity))
        .overlay(GridBorder(width: width, style: node.strokeStyle.map { GridBorderStyle(rawValue: $0.rawValue)! } ?? .solid, color: stroke, radius: radius))
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .padding(padding)
        .accessibilityHidden(true)
    default:
      GridPolygonShape(node: node, fill: fill, stroke: stroke)
        .frame(width: size.width, height: size.height)
        .offset(x: padding, y: padding)
        .accessibilityHidden(true)
    }
  }
}

/// Ellipses, polygons, stars, lines and arrows in a 0–100 viewBox. Circles keep their aspect
/// ratio; everything else stretches, strokes included, as with `preserveAspectRatio="none"`.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridPolygonShape: View {
  let node: GridBuiltinNode
  let fill: Color
  let stroke: Color

  var body: some View {
    Canvas { context, size in
      let shape = node.shape
      var path = Path()
      switch shape {
      case .ellipse, .circle:
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 96, height: 96))
      case .line:
        path.move(to: CGPoint(x: 2, y: 50))
        path.addLine(to: CGPoint(x: 98, y: 50))
      case .arrow:
        path.move(to: CGPoint(x: 2, y: 50))
        path.addLine(to: CGPoint(x: 96, y: 50))
        path.move(to: CGPoint(x: 70, y: 24))
        path.addLine(to: CGPoint(x: 96, y: 50))
        path.addLine(to: CGPoint(x: 70, y: 76))
      default:
        let sides: Int
        switch shape {
        case .triangle: sides = 3
        case .pentagon: sides = 5
        case .hexagon: sides = 6
        case .heptagon: sides = 7
        case .octagon: sides = 8
        case .star: sides = 5
        default: sides = node.polygonSides ?? 6
        }
        let points = GridPolygonShape.points(sides: sides, star: shape == .star)
        path.addLines(points)
        path.closeSubpath()
      }
      let scale: CGAffineTransform
      if shape == .circle {
        let s = min(size.width, size.height) / 100
        scale = CGAffineTransform(translationX: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2).scaledBy(x: s, y: s)
      } else {
        scale = CGAffineTransform(scaleX: size.width / 100, y: size.height / 100)
      }
      let filled = shape != .line && shape != .arrow
      if filled {
        context.fill(path.applying(scale), with: .color(fill.opacity(node.appearance.colorOpacity ?? 1)))
      }
      let width = CGFloat(node.strokeWidth ?? (shape == .line || shape == .arrow ? 2 : 0))
      if width > 0 {
        let dash: [CGFloat] =
          node.strokeStyle == .dashed ? [6, 4] : node.strokeStyle == .dotted ? [1, 3] : []
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
        // Stroke in viewBox units, then stretch the outline: SVG scales strokes with the viewBox.
        context.fill(path.strokedPath(style).applying(scale), with: .color(stroke))
      }
    }
  }

  /// `polygonPoints`: radius 48 (inner 21 for stars), first point at the top.
  static func points(sides: Int, star: Bool) -> [CGPoint] {
    let count = star ? sides * 2 : sides
    return (0..<count).map { index in
      let angle = Double(index) * Double.pi * 2 / Double(count) - Double.pi / 2
      let radius: Double = star && index % 2 == 1 ? 21 : 48
      return CGPoint(x: 50 + cos(angle) * radius, y: 50 + sin(angle) * radius)
    }
  }
}

/// CSS-like borders drawn inside the box. `double` draws two lines; `groove` and `ridge`
/// have no native equivalent and render as solid (documented fallback).
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridBorder: View {
  let width: CGFloat
  let style: GridBorderStyle
  let color: Color
  let radius: CGFloat

  var body: some View {
    if width > 0 {
      switch style {
      case .double where width >= 3:
        let line = width / 3
        ZStack {
          RoundedRectangle(cornerRadius: radius).strokeBorder(color, lineWidth: line)
          RoundedRectangle(cornerRadius: max(0, radius - 2 * line)).strokeBorder(color, lineWidth: line)
            .padding(2 * line)
        }
      case .dashed:
        RoundedRectangle(cornerRadius: radius)
          .strokeBorder(color, style: StrokeStyle(lineWidth: width, dash: [width * 3, width * 3]))
      case .dotted:
        RoundedRectangle(cornerRadius: radius)
          .strokeBorder(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [0, width * 2]))
      default:
        RoundedRectangle(cornerRadius: radius).strokeBorder(color, lineWidth: width)
      }
    }
  }
}

/// Draws a resolved static SVG.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridSVGView: View {
  let drawing: GridSVGDrawing?
  /// `currentColor` for inline icons; SVG files shown as images use black.
  var currentColor: Color = .black
  /// Icons fill the box using only the viewBox (the web sizes the inline <svg> to 100%).
  var fitViewBoxOnly = false

  var body: some View {
    Canvas { context, size in
      guard let drawing else { return }
      let box = drawing.viewBox
      // object-fit: contain for the image's intrinsic size, then the viewBox inside it.
      var area = CGRect(origin: .zero, size: size)
      if !fitViewBoxOnly {
        let scale = min(size.width / drawing.intrinsicWidth, size.height / drawing.intrinsicHeight)
        let fitted = CGSize(width: drawing.intrinsicWidth * scale, height: drawing.intrinsicHeight * scale)
        area = CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
      }
      var sx = area.width / box.width
      var sy = area.height / box.height
      var tx = area.minX - box.x * sx
      var ty = area.minY - box.y * sy
      if let align = drawing.align {
        let s = drawing.slice ? max(sx, sy) : min(sx, sy)
        sx = s
        sy = s
        tx = area.minX + (area.width - box.width * s) * align.x - box.x * s
        ty = area.minY + (area.height - box.height * s) * align.y - box.y * s
      }
      let view = CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: tx, ty: ty)
      context.clip(to: Path(area))
      for shape in drawing.shapes {
        var path = Path()
        for command in shape.commands {
          switch command {
          case .move(let x, let y): path.move(to: CGPoint(x: x, y: y))
          case .line(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
          case .cubic(let x1, let y1, let x2, let y2, let x, let y):
            path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
          case .close: path.closeSubpath()
          }
        }
        let t = shape.transform
        let user = CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty).concatenating(view)
        if let fill = shape.fill {
          context.fill(path.applying(user), with: .color(color(fill)), style: FillStyle(eoFill: shape.evenOdd))
        }
        if let stroke = shape.stroke, shape.strokeWidth > 0 {
          let style = StrokeStyle(
            lineWidth: shape.strokeWidth, lineCap: shape.lineCap == "round" ? .round : shape.lineCap == "square" ? .square : .butt,
            lineJoin: shape.lineJoin == "round" ? .round : shape.lineJoin == "bevel" ? .bevel : .miter,
            miterLimit: shape.miterLimit, dash: shape.dash.map { CGFloat($0) }, dashPhase: shape.dashOffset)
          context.fill(path.strokedPath(style).applying(user), with: .color(color(stroke)))
        }
      }
    }
  }

  func color(_ paint: GridSVGPaint) -> Color {
    switch paint {
    case .color(let rgba): rgba.swiftUI
    case .currentColor(let opacity): currentColor.opacity(opacity)
    }
  }
}

/// An uploaded SVG: validated, parsed and drawn natively; anything the native drawer cannot
/// reproduce shows the web renderer's failure fallback with a download link.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridSVGAssetView: View {
  let url: URL
  let name: String
  let messages: GridMessages
  @EnvironmentObject private var store: GridAssetStore

  var body: some View {
    let _ = store.revision
    Group {
      switch store.drawing(url) {
      case .success(let drawing)?:
        GridSVGView(drawing: drawing).accessibilityLabel(Text(name)).accessibilityAddTraits(.isImage)
      case .failure?:
        VStack(spacing: 8) {
          Text(messages.unavailable)
          GridLinkButton(url: url) { Text(messages.download).underline() }
        }
        .font(.system(size: 12, weight: .medium))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case nil:
        Color.clear
      }
    }
    .task(id: url) { await store.loadSVG(url) }
  }
}

/// The web renderer's centred 12-point placeholder.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridPlaceholder: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .medium))
      .lineSpacing(12 * 0.4 - 2)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
