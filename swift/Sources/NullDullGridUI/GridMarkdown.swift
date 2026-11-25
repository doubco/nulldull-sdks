import Foundation
import NullDullGrid

/// A styled run of inline text. Links are present only when they pass the safe-URL check.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridInline: Hashable, Sendable {
  var text: String
  var bold = false
  var italic = false
  var code = false
  var strike = false
  var link: URL?
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct GridListItem: Hashable, Sendable {
  var ordinal: Int
  /// GitHub task-list state, when the item starts with `[ ]` or `[x]`.
  var checked: Bool?
  var blocks: [GridBlock]
}

@available(iOS 16, macOS 13, tvOS 16, *)
enum GridColumnAlignment: Hashable, Sendable { case left, center, right }

@available(iOS 16, macOS 13, tvOS 16, *)
indirect enum GridBlock: Hashable, Sendable {
  case paragraph([GridInline])
  case heading(Int, [GridInline])
  case list(ordered: Bool, items: [GridListItem], depth: Int)
  case quote([GridBlock])
  case code(String)
  case table(alignments: [GridColumnAlignment?], header: [[GridInline]], rows: [[[GridInline]]])
  case rule
  /// Raw HTML, shown as literal text (never interpreted).
  case raw(String)

  /// CSS block margins in em, as the web renderer's stylesheet and browser defaults set them.
  var margins: (top: Double, bottom: Double) {
    switch self {
    case .paragraph: (0, 0.5)
    case .heading: (0.5, 0.5)
    case .list(_, _, let depth): depth == 0 ? (1, 1) : (0, 0)
    case .quote, .code: (1, 1)
    case .rule: (0.5, 0.5)
    case .table, .raw: (0, 0)
    }
  }
}

/// GitHub-flavoured Markdown via Foundation's parser, reduced to the block and
/// inline structure the web renderer (react-markdown + remark-gfm) produces.
/// HTML is never interpreted and images are never fetched (their alt text is shown).
@available(iOS 16, macOS 13, tvOS 16, *)
enum GridMarkdown {
  static func parse(_ source: String, pageURL: ((GridPageLink) -> URL?)? = nil) -> [GridBlock] {
    let options = AttributedString.MarkdownParsingOptions(
      allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
    guard let attributed = try? AttributedString(markdown: source, options: options) else {
      return [.paragraph([GridInline(text: source)])]
    }
    let root = Node(kind: nil, identity: -1)
    for run in attributed.runs {
      let components = Array((run.presentationIntent?.components ?? []).reversed())
      let inline = makeInline(String(attributed[run.range].characters), run, pageURL: pageURL)
      if components.isEmpty {
        // Block HTML carries no block intent: keep it as literal text.
        if let last = root.children.last, last.kind == nil {
          last.inlines.append(inline)
        } else {
          let node = Node(kind: nil, identity: -2 - root.children.count)
          node.inlines.append(inline)
          root.children.append(node)
        }
        continue
      }
      var node = root
      for component in components {
        if let last = node.children.last, last.identity == component.identity {
          node = last
        } else {
          let child = Node(kind: component.kind, identity: component.identity)
          node.children.append(child)
          node = child
        }
      }
      node.inlines.append(inline)
    }
    return blocks(root.children, depth: 0)
  }

  final class Node {
    let kind: PresentationIntent.Kind?
    let identity: Int
    var children: [Node] = []
    var inlines: [GridInline] = []
    init(kind: PresentationIntent.Kind?, identity: Int) {
      self.kind = kind
      self.identity = identity
    }
  }

  static func makeInline(_ text: String, _ run: AttributedString.Runs.Run, pageURL: ((GridPageLink) -> URL?)?) -> GridInline {
    let intent = run.inlinePresentationIntent ?? []
    var inline = GridInline(text: text)
    // Soft line breaks stay visible: the web renderer uses `white-space: pre-wrap`.
    if intent.contains(.softBreak) { inline.text = "\n" }
    inline.bold = intent.contains(.stronglyEmphasized)
    inline.italic = intent.contains(.emphasized)
    inline.code = intent.contains(.code)
    inline.strike = intent.contains(.strikethrough)
    if let destination = run.link?.absoluteString {
      if let link = GridPageLink(destination: destination) { inline.link = pageURL?(link) }
      else if let href = GridURL.safeHref(destination) { inline.link = URL(string: href) }
    }
    return inline
  }

  static func blocks(_ nodes: [Node], depth: Int) -> [GridBlock] {
    nodes.compactMap { node -> GridBlock? in
      guard let kind = node.kind else {
        let text = node.inlines.map(\.text).joined()
        return .raw(text.hasSuffix("\n") ? String(text.dropLast()) : text)
      }
      switch kind {
      case .paragraph: return .paragraph(node.inlines)
      case .header(let level): return .heading(level, node.inlines)
      case .orderedList, .unorderedList:
        let items = node.children.map { item -> GridListItem in
          var ordinal = 1
          if case .listItem(let value)? = item.kind { ordinal = value }
          var children = blocks(item.children, depth: depth + 1)
          var checked: Bool?
          if case .paragraph(var inlines)? = children.first, let first = inlines.first {
            for (prefix, state) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where first.text.hasPrefix(prefix) {
              checked = state
              inlines[0].text.removeFirst(prefix.count)
              children[0] = .paragraph(inlines)
            }
          }
          return GridListItem(ordinal: ordinal, checked: checked, blocks: children)
        }
        if case .orderedList = kind { return .list(ordered: true, items: items, depth: depth) }
        return .list(ordered: false, items: items, depth: depth)
      case .blockQuote: return .quote(blocks(node.children, depth: depth))
      case .codeBlock:
        let text = node.inlines.map(\.text).joined()
        return .code(text.hasSuffix("\n") ? String(text.dropLast()) : text)
      case .thematicBreak: return .rule
      case .table(let columns):
        let alignments = columns.map { column -> GridColumnAlignment? in
          switch column.alignment {
          case .left: .left
          case .center: .center
          case .right: .right
          @unknown default: nil
          }
        }
        func cells(_ row: Node) -> [[GridInline]] {
          var result = Array(repeating: [GridInline](), count: columns.count)
          for cell in row.children {
            if case .tableCell(let index)? = cell.kind, index < result.count { result[index] = cell.inlines }
          }
          return result
        }
        var header: [[GridInline]] = []
        var rows: [[[GridInline]]] = []
        for row in node.children {
          if case .tableHeaderRow? = row.kind { header = cells(row) } else { rows.append(cells(row)) }
        }
        return .table(alignments: alignments, header: header, rows: rows)
      default:
        let text = node.inlines.map(\.text).joined()
        return text.isEmpty ? nil : .paragraph(node.inlines)
      }
    }
  }
}
