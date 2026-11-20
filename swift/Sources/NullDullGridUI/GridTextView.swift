import CoreText
import Foundation
import NullDullGrid
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Typography shared by every block of one text node.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridTextStyle {
  var family: GridFontFamily
  var descriptor: CTFontDescriptor?
  var size: CGFloat
  var lineHeight: CGFloat
  var align: GridAlign
  var color: Color
  /// Width of the text box's content area (needed for the drop cap).
  var width: CGFloat

  var base: CTFont { GridFonts.base(family, size: size, descriptor: descriptor) }
  func font(bold: Bool = false, italic: Bool = false, code: Bool = false, scale: CGFloat = 1) -> CTFont {
    let font = scale == 1 ? base : GridFonts.base(family, size: size * scale, descriptor: descriptor)
    return GridFonts.variant(font, bold: bold, italic: italic, mono: code)
  }
  /// CSS `line-height` is a multiple of the font size; SwiftUI adds spacing between lines only,
  /// so half the extra leading also goes above the first and below the last line.
  var extraLeading: CGFloat { max(0, lineHeight * size - GridFonts.naturalLineHeight(base)) }
  var textAlignment: TextAlignment {
    switch align {
    case .left, .justify: .leading
    case .center: .center
    case .right: .trailing
    }
  }
  var frameAlignment: Alignment {
    switch align {
    case .left, .justify: .leading
    case .center: .center
    case .right: .trailing
    }
  }

  func attributed(_ inlines: [GridInline], bold: Bool = false) -> AttributedString {
    var result = AttributedString()
    for inline in inlines {
      var part = AttributedString(inline.text)
      part.font = Font(font(bold: bold || inline.bold, italic: inline.italic, code: inline.code))
      if inline.strike { part.strikethroughStyle = .single }
      if let link = inline.link {
        part.link = link
        part.underlineStyle = .single
      }
      result += part
    }
    return result
  }

  func nsAttributed(_ inlines: [GridInline]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for inline in inlines {
      let font = font(bold: inline.bold, italic: inline.italic, code: inline.code)
      result.append(NSAttributedString(string: inline.text, attributes: [.init(kCTFontAttributeName as String): font]))
    }
    return result
  }
}

/// The text node: Markdown blocks with padding, vertical alignment, colour opacity,
/// optional drop cap and optional fit-to-box sizing.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridTextView: View {
  let node: GridBuiltinNode
  let contentSized: Bool
  /// The box's content size (inside borders); its height is ignored when content-sized.
  let boxSize: CGSize
  let color: Color
  let descriptor: CTFontDescriptor?
  let typeScale: CGFloat

  var body: some View {
    let padding = CGFloat(node.appearance.padding ?? 8)
    let blocks = GridMarkdown.parse(node.text)
    var style = GridTextStyle(
      family: node.fontFamily ?? .sans, descriptor: descriptor, size: CGFloat(node.fontSize) * typeScale,
      lineHeight: CGFloat(node.lineHeight ?? 1.2), align: node.align, color: color,
      width: max(0, boxSize.width - padding * 2))
    if node.fitToBox == true, !contentSized {
      style.size = GridTextFitter.fittedSize(
        blocks: blocks, style: style, dropcap: node.dropcap == true,
        width: boxSize.width - padding * 2, height: boxSize.height - padding * 2)
    }
    let alignment: Alignment
    switch node.verticalAlign ?? .top {
    case .top: alignment = .top
    case .middle: alignment = .center
    case .bottom: alignment = .bottom
    }
    return GridBlocksView(blocks: blocks, style: style, dropcap: node.dropcap == true)
      .fixedSize(horizontal: false, vertical: true)
      .padding(padding)
      // Zero minimums keep the box at its frame size, so overflowing text spills (and is clipped)
      // around the vertical alignment as CSS does, instead of growing the box.
      .frame(minWidth: 0, maxWidth: .infinity, minHeight: contentSized ? nil : 0, maxHeight: contentSized ? nil : .infinity, alignment: alignment)
      .opacity(node.appearance.colorOpacity ?? 1)
  }
}

/// Vertical block stack with collapsed CSS margins.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridBlocksView: View {
  let blocks: [GridBlock]
  let style: GridTextStyle
  var dropcap = false
  var nested = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
        GridBlockView(block: block, style: style, dropcap: dropcap && index == 0)
          .padding(.top, index == 0 ? 0 : spacing(before: index))
      }
    }
    .frame(maxWidth: .infinity, alignment: style.frameAlignment)
  }

  func spacing(before index: Int) -> CGFloat {
    // Adjacent vertical margins collapse to the larger one.
    CGFloat(max(blocks[index - 1].margins.bottom, blocks[index].margins.top)) * style.size
  }
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct GridBlockView: View {
  let block: GridBlock
  let style: GridTextStyle
  var dropcap = false

  var body: some View {
    switch block {
    case .paragraph(let inlines):
      if dropcap, let split = GridDropCap.split(inlines, style: style) {
        GridDropCapView(split: split, style: style)
      } else {
        paragraph(style.attributed(inlines))
      }
    case .heading(let level, let inlines):
      paragraph(style.attributed(inlines, bold: true))
        .accessibilityAddTraits(.isHeader)
        .accessibilityHeading(level == 1 ? .h1 : level == 2 ? .h2 : level == 3 ? .h3 : level == 4 ? .h4 : level == 5 ? .h5 : .h6)
    case .raw(let text):
      // Outside a paragraph the web collapses whitespace.
      paragraph(AttributedString(text.split(whereSeparator: \.isWhitespace).joined(separator: " ")).withFont(style.base))
    case .list(let ordered, let items, let depth):
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(marker(ordered: ordered, item: item, depth: depth))
              .lineLimit(1)
              .fixedSize()
              // A larger bullet glyph must not make the line taller.
              .frame(height: GridFonts.naturalLineHeight(style.base))
              .frame(width: 1.3 * style.size, alignment: .trailing)
              .padding(.vertical, style.extraLeading / 2)
              .accessibilityHidden(item.checked == nil)
            GridBlocksView(blocks: item.blocks, style: style, nested: true)
          }
        }
      }
    case .quote(let blocks):
      GridBlocksView(blocks: blocks, style: style, nested: true)
        .padding(.horizontal, 40)
    case .code(let text):
      // `white-space: pre`: long lines do not wrap. The web scrolls them; here they are clipped.
      Text(AttributedString(text).withFont(style.font(code: true)))
        .lineSpacing(style.extraLeading)
        .padding(.vertical, style.extraLeading / 2)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    case .rule:
      Rectangle().fill(style.color.opacity(0.35)).frame(height: 2).frame(maxWidth: .infinity)
    case .table(let alignments, let header, let rows):
      GridTableView(alignments: alignments, header: header, rows: rows, style: style)
    }
  }

  func paragraph(_ text: AttributedString) -> some View {
    Text(text)
      .lineSpacing(style.extraLeading)
      .padding(.vertical, style.extraLeading / 2)
      .multilineTextAlignment(style.textAlignment)
      .frame(maxWidth: .infinity, alignment: style.frameAlignment)
      .fixedSize(horizontal: false, vertical: true)
  }

  func marker(ordered: Bool, item: GridListItem, depth: Int) -> AttributedString {
    var text: AttributedString
    if let checked = item.checked {
      text = AttributedString(checked ? "☑ " : "☐ ")
    } else if ordered {
      text = AttributedString("\(item.ordinal). ")
    } else {
      // Browser defaults: disc, then circle, then square, drawn about a third of an em wide.
      var bullet = AttributedString([0: "•", 1: "◦"][depth] ?? "▪")
      bullet.font = Font(style.font(scale: 1.5))
      bullet.baselineOffset = -0.12 * style.size
      text = bullet + AttributedString("  ")
    }
    text.mergeAttributes(AttributeContainer().font(Font(style.base)), mergePolicy: .keepCurrent)
    return text
  }
}

@available(iOS 16, macOS 13, tvOS 16, *)
extension AttributedString {
  func withFont(_ font: CTFont) -> AttributedString {
    var copy = self
    copy.font = Font(font)
    return copy
  }
}

/// GFM tables: collapsed 1-point borders in the text colour, 0.25em cell padding,
/// bold centred header cells, full width.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridTableView: View {
  let alignments: [GridColumnAlignment?]
  let header: [[GridInline]]
  let rows: [[[GridInline]]]
  let style: GridTextStyle

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
      if !header.isEmpty {
        GridRow {
          ForEach(Array(header.enumerated()), id: \.offset) { column, cell in
            self.cell(cell, column: column, header: true)
          }
        }
      }
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        GridRow {
          ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
            self.cell(cell, column: column, header: false)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  func cell(_ inlines: [GridInline], column: Int, header: Bool) -> some View {
    // Foundation reports unaligned GFM columns as left, so `left` means "unspecified" here.
    let explicit = column < alignments.count ? alignments[column] : nil
    let alignment: Alignment
    let text: TextAlignment
    switch explicit {
    case .center?: (alignment, text) = (.center, .center)
    case .right?: (alignment, text) = (.trailing, .trailing)
    default: (alignment, text) = header ? (.center, .center) : (style.frameAlignment, style.textAlignment)
    }
    return Text(style.attributed(inlines, bold: header))
      .lineSpacing(style.extraLeading)
      .multilineTextAlignment(text)
      .padding(.vertical, style.extraLeading / 2)
      .padding(0.25 * style.size)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
      .overlay(Rectangle().stroke(style.color, lineWidth: 1))
  }
}

// MARK: - Drop cap

@available(iOS 16, macOS 13, tvOS 16, *)
struct GridDropCapSplit {
  var cap: String
  var capWidth: CGFloat
  /// The paragraph after the floated letter.
  var rest: [GridInline]
}

/// Emulates `::first-letter { float: left; font-size: 3.2em; line-height: .85; padding: .08em .1em 0 0 }`:
/// Core Text finds where the lines beside the floated letter end at the text width, and the
/// paragraph continues at full width below it.
@available(iOS 16, macOS 13, tvOS 16, *)
enum GridDropCap {
  static func split(_ inlines: [GridInline], style: GridTextStyle) -> GridDropCapSplit? {
    guard var first = inlines.first, !first.text.isEmpty else { return nil }
    var characters = Array(first.text)
    var cap = ""
    // ::first-letter includes leading punctuation such as opening quotes.
    while let character = characters.first, character.isPunctuation, cap.count < 3 {
      cap.append(character)
      characters.removeFirst()
    }
    guard let letter = characters.first, !letter.isWhitespace else { return nil }
    cap.append(letter)
    characters.removeFirst()
    first.text = String(characters)
    var rest = inlines
    rest[0] = first
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: cap, attributes: [.init(kCTFontAttributeName as String): capFont(first, style)]))
    let capWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + 0.1 * 3.2 * style.size
    return GridDropCapSplit(cap: cap, capWidth: capWidth, rest: rest)
  }

  static func capFont(_ first: GridInline, _ style: GridTextStyle) -> CTFont {
    style.font(bold: first.bold, italic: first.italic, scale: 3.2)
  }

  /// Splits the paragraph after the lines that sit beside the floated letter.
  static func divide(_ split: GridDropCapSplit, style: GridTextStyle, width: CGFloat) -> (beside: [GridInline], below: [GridInline]) {
    let floatHeight = (0.85 + 0.08) * 3.2 * style.size
    let lines = max(1, Int((floatHeight / (style.lineHeight * style.size)).rounded(.up)))
    let framesetter = CTFramesetterCreateWithAttributedString(style.nsAttributed(split.rest))
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: max(1, width - split.capWidth), height: 100_000), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
    guard let ctLines = CTFrameGetLines(frame) as? [CTLine], ctLines.count > lines else { return (split.rest, []) }
    let range = CTLineGetStringRange(ctLines[lines - 1])
    return cut(split.rest, at: range.location + range.length)
  }

  /// Splits inline runs at a UTF-16 offset.
  static func cut(_ inlines: [GridInline], at offset: Int) -> ([GridInline], [GridInline]) {
    var before: [GridInline] = []
    var after: [GridInline] = []
    var position = 0
    for inline in inlines {
      let length = inline.text.utf16.count
      if position + length <= offset {
        before.append(inline)
      } else if position >= offset {
        after.append(inline)
      } else {
        let index = String.Index(utf16Offset: offset - position, in: inline.text)
        var head = inline
        var tail = inline
        head.text = String(inline.text[..<index])
        tail.text = String(inline.text[index...])
        before.append(head)
        after.append(tail)
      }
      position += length
    }
    // Drop the whitespace the line break consumed.
    while var first = after.first, first.text.first == " " || first.text.first == "\n" {
      first.text.removeFirst()
      if first.text.isEmpty { after.removeFirst() } else { after[0] = first }
    }
    while var last = before.last, last.text.last == " " || last.text.last == "\n" {
      last.text.removeLast()
      if last.text.isEmpty { before.removeLast() } else { before[before.count - 1] = last }
    }
    return (before, after)
  }
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct GridDropCapView: View {
  let split: GridDropCapSplit
  let style: GridTextStyle

  var body: some View {
    let parts = GridDropCap.divide(split, style: style, width: style.width)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        Text(split.cap)
          .font(Font(GridDropCap.capFont(split.rest.first ?? GridInline(text: ""), style)))
          .fixedSize()
          .frame(width: split.capWidth, height: 0.85 * 3.2 * style.size, alignment: .leading)
          .padding(.top, 0.08 * 3.2 * style.size)
        text(parts.beside)
      }
      if !parts.below.isEmpty { text(parts.below) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(split.cap + split.rest.map(\.text).joined()))
  }

  func text(_ inlines: [GridInline]) -> some View {
    Text(style.attributed(inlines))
      .lineSpacing(style.extraLeading)
      .padding(.vertical, style.extraLeading / 2)
      .multilineTextAlignment(style.textAlignment)
      .frame(maxWidth: .infinity, alignment: style.frameAlignment)
      .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Fit to box

/// `fitToBox`: the largest whole point size from 8 to 256 whose rendered height fits the box,
/// found by binary search over real SwiftUI measurements.
@available(iOS 16, macOS 13, tvOS 16, *)
@MainActor
enum GridTextFitter {
  private static var cache: [String: CGFloat] = [:]

  static func fittedSize(blocks: [GridBlock], style: GridTextStyle, dropcap: Bool, width: CGFloat, height: CGFloat)
    -> CGFloat
  {
    guard width > 0, height > 0 else { return 8 }
    let key = "\(blocks.hashValue)|\(style.family)|\(style.descriptor.map { CFHash($0) } ?? 0)|\(style.lineHeight)|\(width)|\(height)|\(dropcap)"
    if let cached = cache[key] { return cached }
    var low = 8
    var high = 256
    var best = 8
    while low <= high {
      let size = (low + high) / 2
      var candidate = style
      candidate.size = CGFloat(size)
      let measured = measure(GridBlocksView(blocks: blocks, style: candidate, dropcap: dropcap), width: width)
      if measured.height <= height + 1 && measured.width <= width + 1 {
        best = size
        low = size + 1
      } else {
        high = size - 1
      }
    }
    if cache.count > 256 { cache.removeAll() }
    cache[key] = CGFloat(best)
    return CGFloat(best)
  }

  static func measure(_ view: some View, width: CGFloat) -> CGSize {
    let root = view.fixedSize(horizontal: false, vertical: true).frame(width: width)
    let target = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    #if canImport(UIKit)
      return UIHostingController(rootView: root).sizeThatFits(in: target)
    #else
      return NSHostingController(rootView: root).sizeThatFits(in: target)
    #endif
  }
}
