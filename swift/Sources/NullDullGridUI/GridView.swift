import Foundation
import NullDullGrid
import SwiftUI

/// Application views for custom nodes, keyed by `nodeKey`.
///
/// Custom node properties are inert strings. Only components you register here run;
/// unregistered keys show an inert placeholder (or `unknown`, if set).
@available(iOS 16, macOS 13, tvOS 16, *)
@MainActor
public struct GridCustomNodeRegistry {
  var renderers: [String: (GridCustomNode) -> AnyView] = [:]
  var unknown: ((GridCustomNode) -> AnyView)?

  public init() {}

  /// Registers a view for nodes whose `nodeKey` equals `key` exactly.
  public func register<V: View>(_ key: String, @ViewBuilder _ render: @escaping (GridCustomNode) -> V) -> Self {
    var copy = self
    copy.renderers[key] = { AnyView(render($0)) }
    return copy
  }

  /// Replaces the placeholder shown for unregistered keys.
  public func unknown<V: View>(@ViewBuilder _ render: @escaping (GridCustomNode) -> V) -> Self {
    var copy = self
    copy.unknown = { AnyView(render($0)) }
    return copy
  }

  public func renderer(for key: String) -> ((GridCustomNode) -> AnyView)? { renderers[key] }
}

/// Renders a Grid document natively.
///
/// The container width selects the breakpoint, exactly as on the web. Give `width` when you
/// know it (for example in a fixed-width cell) to skip the measuring pass; otherwise the view
/// takes the width its container proposes, starts from `initialWidth` until it has measured it,
/// and follows it as it narrows or widens (rotation, window resizing, split view).
@available(iOS 16, macOS 13, tvOS 16, *)
public struct GridView: View {
  let document: GridDocument
  let resolveAsset: (String) -> URL?
  let width: CGFloat?
  let initialWidth: CGFloat
  let override: GridActiveLayout?
  let theme: GridTheme
  let customNodes: GridCustomNodeRegistry
  let embed: ((GridBuiltinNode) -> AnyView)?
  let messages: GridMessages
  let label: String?
  let dynamicType: GridDynamicType
  @State private var measured: CGFloat?
  @Environment(\.gridAssetStore) private var store

  /// - Parameters:
  ///   - resolveAsset: maps Grid asset IDs to absolute http(s) URLs. Other schemes are ignored.
  ///   - layout, breakpointId: render a specific layout instead of choosing one by width.
  ///   - embed: replaces the built-in embed card, e.g. with a consent-aware inline player.
  public init(
    document: GridDocument,
    resolveAsset: @escaping (String) -> URL? = { _ in nil },
    width: CGFloat? = nil,
    initialWidth: CGFloat = 390,
    layout: GridLayoutSettings? = nil,
    breakpointId: String? = nil,
    theme: GridTheme = GridTheme(),
    customNodes: GridCustomNodeRegistry = GridCustomNodeRegistry(),
    embed: ((GridBuiltinNode) -> AnyView)? = nil,
    messages: GridMessages = GridMessages(),
    label: String? = nil,
    dynamicType: GridDynamicType = .contentFlowText
  ) {
    self.document = document
    self.resolveAsset = resolveAsset
    self.width = width
    self.initialWidth = initialWidth
    self.override = layout.map { GridActiveLayout(layout: $0, breakpointId: breakpointId) }
    self.theme = theme
    self.customNodes = customNodes
    self.embed = embed
    self.messages = messages
    self.label = label
    self.dynamicType = dynamicType
  }

  public var body: some View {
    let viewport = Self.viewport(width: width, measured: measured, initialWidth: initialWidth)
    let canvas = GridCanvasView(
      document: document, viewport: viewport, override: override, asset: safeAsset, theme: theme,
      customNodes: customNodes, embed: embed, messages: messages, dynamicType: dynamicType)
    Group {
      if let width {
        canvas.frame(width: width)
      } else {
        canvas.readingProposedWidth { measured = $0 }
      }
    }
    .environmentObject(store)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label.map { Text($0) } ?? Text(""))
  }

  /// Asset URLs must be absolute, credential-free http(s).
  func safeAsset(_ id: String) -> URL? {
    guard let url = resolveAsset(id), let href = GridURL.safeHref(url.absoluteString) else { return nil }
    return URL(string: href)
  }

  /// The canvas width: an explicit `width` wins, then the last measured width, then `initialWidth`.
  static func viewport(width: CGFloat?, measured: CGFloat?, initialWidth: CGFloat) -> CGFloat {
    width ?? measured ?? initialWidth
  }
}

@available(iOS 16, macOS 13, tvOS 16, *)
extension View {
  /// Takes the width the parent proposes, whatever this view's own width, and reports it.
  ///
  /// `GridView` sizes its canvas from the reported width, so the frame must not depend on the
  /// canvas: with only `maxWidth: .infinity`, a flexible frame is never narrower than its child,
  /// and a canvas laid out at a wider width would keep the measurement from ever shrinking.
  /// `minWidth: 0` makes the frame exactly as wide as a finite proposal. Height still follows the
  /// child, so this works in a vertical `ScrollView`. Without a width proposal (for example in a
  /// horizontal `ScrollView`) the frame takes the child's width, which reports the current width
  /// again and changes nothing.
  func readingProposedWidth(_ action: @escaping (CGFloat) -> Void) -> some View {
    frame(minWidth: 0, maxWidth: .infinity)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
        if width.isFinite, width > 0 { action(width) }
      }
  }
}

/// Renders a page returned by `GridPublicClient` with its pinned assets.
@available(iOS 16, macOS 13, tvOS 16, *)
public struct PublishedGridPageView: View {
  let content: GridView

  public init(
    page: PublicGridPage, width: CGFloat? = nil, initialWidth: CGFloat = 390, theme: GridTheme = GridTheme(),
    customNodes: GridCustomNodeRegistry = GridCustomNodeRegistry(), embed: ((GridBuiltinNode) -> AnyView)? = nil,
    messages: GridMessages = GridMessages(), dynamicType: GridDynamicType = .contentFlowText
  ) {
    let assets = page.assetURLs
    content = GridView(
      document: page.document, resolveAsset: { assets[$0].flatMap(URL.init(string:)) }, width: width,
      initialWidth: initialWidth, theme: theme, customNodes: customNodes, embed: embed, messages: messages,
      label: page.title, dynamicType: dynamicType)
  }

  public var body: some View { content }
}

/// The canvas for one viewport width.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridCanvasView: View {
  let document: GridDocument
  let viewport: CGFloat
  let override: GridActiveLayout?
  let asset: (String) -> URL?
  let theme: GridTheme
  let customNodes: GridCustomNodeRegistry
  let embed: ((GridBuiltinNode) -> AnyView)?
  let messages: GridMessages
  let dynamicType: GridDynamicType
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @EnvironmentObject private var store: GridAssetStore

  var body: some View {
    let active = override ?? GridGeometry.activeLayout(document, width: Double(viewport))
    let layout = active.layout
    // Widths and fixed geometry do not depend on text measurement; heights of flowing text
    // are measured by `GridCanvasLayout` from the rendered views.
    let preview = GridGeometry.layout(document, width: Double(viewport), active: active) { _, _ in 0 }
    let foreground = withOpacity(themeColor(layout.color, theme.foreground ?? .primary), layout.appearance.colorOpacity)
    let background = themeColor(layout.background, theme.background ?? .clear)
    let scale = dynamicType == .never || !preview.isFlow ? 1 : GridTypeScale.factor(dynamicTypeSize)
    let fonts = fontURLs()
    let canvas = GridCanvasLayout(document: document, viewport: Double(viewport), active: active) {
      ForEach(Array(preview.nodes.enumerated()), id: \.element.node.id) { index, placed in
        GridNodeView(
          placed: placed, foreground: foreground, asset: asset, fontURL: fontURL(placed.node, fonts), customNodes: customNodes,
          embed: embed, messages: messages, typeScale: placed.isFlowing && placed.node.isText ? scale : 1)
          .accessibilitySortPriority(Double(preview.nodes.count - index))
      }
    }
    .background(alignment: .topLeading) {
      ZStack {
        Rectangle().fill(background)
        if let id = layout.appearance.backgroundImage, let url = asset(id) {
          GridBackgroundImage(url: url, fit: layout.appearance.backgroundFit ?? .cover)
        }
      }
      .opacity(layout.appearance.backgroundOpacity ?? 1)
      .clipShape(RoundedRectangle(cornerRadius: CGFloat(layout.radius ?? 0)))
      .accessibilityHidden(true)
    }
    .environment(\.gridForeground, foreground)
    .foregroundStyle(foreground)
    // Authored geometry and alignment are physical, as on the web; text still shapes bidirectionally.
    .environment(\.layoutDirection, .leftToRight)
    .task(id: fonts) { for url in fonts { await store.loadFont(url) } }

    if preview.canvasWidth > Double(viewport) + 0.5 {
      ScrollView(.horizontal) { canvas }.frame(width: viewport)
    } else {
      canvas.frame(width: viewport)
    }
  }

  /// Uploaded fonts of visible text nodes: at most eight distinct URLs, like the web renderer.
  func fontURLs() -> [URL] {
    var urls: [URL] = []
    for case .builtin(let node) in document.nodes where node.kind == .text && !node.hidden {
      guard let id = node.fontAsset, let url = asset(id), !urls.contains(url) else { continue }
      urls.append(url)
    }
    return Array(urls.prefix(GridLimits.maxFonts))
  }

  func fontURL(_ node: GridNode, _ allowed: [URL]) -> URL? {
    guard case .builtin(let builtin) = node, let id = builtin.fontAsset, let url = asset(id), allowed.contains(url) else {
      return nil
    }
    return url
  }
}

/// Places node views with the shared layout engine. Flowing text is measured from the
/// rendered SwiftUI view at its column width, so intrinsic heights include loaded fonts.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridCanvasLayout: Layout {
  let document: GridDocument
  let viewport: Double
  let active: GridActiveLayout

  struct Cache {
    var geometry: GridCanvasGeometry?
  }

  func makeCache(subviews: Subviews) -> Cache { Cache() }
  func updateCache(_ cache: inout Cache, subviews: Subviews) { cache.geometry = nil }

  func geometry(_ subviews: Subviews, _ cache: inout Cache) -> GridCanvasGeometry {
    if let geometry = cache.geometry { return geometry }
    let visible = document.nodes.filter { !$0.hidden }.map(\.id)
    let index = Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($1, $0) })
    let geometry = GridGeometry.layout(document, width: viewport, active: active) { node, width in
      guard let i = index[node.id], i < subviews.count else { return 0 }
      return Double(subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }
    cache.geometry = geometry
    return geometry
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
    let geometry = geometry(subviews, &cache)
    return CGSize(width: geometry.canvasWidth, height: geometry.canvasHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
    let geometry = geometry(subviews, &cache)
    for (placed, subview) in zip(geometry.nodes, subviews) {
      subview.place(
        at: CGPoint(x: bounds.minX + placed.rect.x, y: bounds.minY + placed.rect.y), anchor: .topLeading,
        proposal: ProposedViewSize(width: placed.rect.width, height: placed.rect.height))
    }
  }
}
