import Foundation
import NullDullGrid
import SwiftUI

/// One node: opacity, rotation, background, border, radius, content and whole-node link.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridNodeView: View {
  let placed: GridPlacedNode
  let foreground: Color
  let asset: (String) -> URL?
  let fontURL: URL?
  let customNodes: GridCustomNodeRegistry
  let embed: ((GridBuiltinNode) -> AnyView)?
  let messages: GridMessages
  let typeScale: CGFloat
  @EnvironmentObject private var store: GridAssetStore

  var body: some View {
    let size = CGSize(width: placed.rect.width, height: placed.rect.height)
    Group {
      switch placed.node {
      case .custom(let node):
        custom(node)
          .frame(width: size.width, height: size.height)
          .foregroundStyle(foreground)
      case .builtin(let node):
        builtin(node, size: size)
      }
    }
    .opacity(placed.node.opacity)
    .rotationEffect(.degrees(placed.node.builtin?.rotation ?? 0))
  }

  @ViewBuilder
  func custom(_ node: GridCustomNode) -> some View {
    if let render = customNodes.renderer(for: node.nodeKey) {
      render(node)
    } else if let unknown = customNodes.unknown {
      unknown(node)
    } else {
      GridPlaceholder(text: node.nodeKey)
    }
  }

  func builtin(_ node: GridBuiltinNode, size: CGSize) -> some View {
    let color = themeColor(node.color, foreground)
    let border = CGFloat(node.borderWidth ?? 0)
    let radius = CGFloat(node.radius)
    let inner = CGSize(width: max(0, size.width - 2 * border), height: max(0, size.height - 2 * border))
    let contentSized = placed.isContentSized
    return ZStack(alignment: .topLeading) {
      ZStack {
        Rectangle().fill(themeColor(node.background, .clear))
        if let id = node.appearance.backgroundImage, let url = asset(id) {
          GridBackgroundImage(url: url, fit: node.appearance.backgroundFit ?? .cover)
        }
      }
      .opacity(node.appearance.backgroundOpacity ?? 1)
      .accessibilityHidden(true)
      content(node, color: color, size: inner)
        .frame(width: inner.width, height: contentSized ? nil : inner.height, alignment: .topLeading)
    }
    .padding(border)
    .frame(width: size.width, height: contentSized ? nil : size.height, alignment: .topLeading)
    .overlay(
      GridBorder(
        width: border, style: node.borderStyle ?? .solid,
        color: withOpacity(themeColor(node.borderColor, foreground), node.borderOpacity), radius: radius))
    .clipShape(RoundedRectangle(cornerRadius: radius))
    .foregroundStyle(color)
    .tint(color)
    .overlay { link(node) }
  }

  @ViewBuilder
  func content(_ node: GridBuiltinNode, color: Color, size: CGSize) -> some View {
    switch node.kind {
    case .text:
      let _ = store.revision
      GridTextView(
        node: node, contentSized: placed.isContentSized, boxSize: size, color: color,
        descriptor: fontURL.flatMap { store.font($0) }, typeScale: typeScale)
    case .separator:
      separator(node)
    case .shape:
      GridShapeView(node: node, foreground: color, assetURL: node.assetId.flatMap(asset), messages: messages, size: size)
    case .embed:
      if let embed {
        embed(node)
      } else {
        // A new URL or name under the same node ID (an updated document) needs a new player and poster state.
        GridEmbedContent(node: node, messages: messages).id(GridEmbedContent.identity(node))
      }
    case .image, .video, .audio:
      if let id = node.assetId, let url = asset(id) {
        switch node.kind {
        case .image: GridImageView(url: url, fit: node.fit, label: node.name)
        case .video: GridVideoView(url: url, label: node.name)
        default: GridAudioView(url: url, label: node.name)
        }
      } else {
        GridPlaceholder(text: messages.chooseAsset)
      }
    }
  }

  /// Empty spacers reserve space; full and centred lines are vertically centred.
  @ViewBuilder
  func separator(_ node: GridBuiltinNode) -> some View {
    let style = node.separatorStyle ?? .empty
    if style != .empty {
      GeometryReader { proxy in
        let width = style == .centered ? proxy.size.width / 2 : proxy.size.width
        Rectangle()
          .fill(withOpacity(themeColor(node.strokeColor, foreground), node.strokeOpacity))
          .frame(width: width, height: CGFloat(node.strokeWidth ?? 1))
          .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
      }
      .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  func link(_ node: GridBuiltinNode) -> some View {
    if let href = GridURL.safeHref(node.link), let url = URL(string: href) {
      GridLinkButton(url: url) { Color.clear.contentShape(Rectangle()) }
        .accessibilityLabel(Text(node.name))
    }
  }
}
