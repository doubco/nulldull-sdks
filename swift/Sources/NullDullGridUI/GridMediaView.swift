import AVKit
import Foundation
import NullDullGrid
import SwiftUI

/// Raster images: cover/contain or a tiled pattern at the image's natural size.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridImageView: View {
  let url: URL
  let fit: GridFit
  let label: String
  @EnvironmentObject private var store: GridAssetStore

  var body: some View {
    let _ = store.revision
    Group {
      if let image = store.image(url) {
        GridImageFill(image: image, fit: fit)
      } else {
        Color.clear
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(label))
    .accessibilityAddTraits(.isImage)
    .task(id: url) { await store.loadImage(url) }
  }
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct GridImageFill: View {
  let image: GridPlatformImage
  let fit: GridFit

  var body: some View {
    switch fit {
    case .tile:
      Image(gridImage: image).resizable(resizingMode: .tile)
    case .contain:
      Image(gridImage: image).resizable().aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .cover:
      Color.clear.overlay(Image(gridImage: image).resizable().aspectRatio(contentMode: .fill)).clipped()
    }
  }
}

/// Background images for layouts and nodes (`background-size: cover|contain|auto`, centred).
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridBackgroundImage: View {
  let url: URL
  let fit: GridFit
  @EnvironmentObject private var store: GridAssetStore

  var body: some View {
    let _ = store.revision
    Group {
      if let image = store.image(url) { GridImageFill(image: image, fit: fit) } else { Color.clear }
    }
    .accessibilityHidden(true)
    .task(id: url) { await store.loadImage(url) }
  }
}

/// Video with system controls; nothing plays until the viewer starts it.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridVideoView: View {
  let url: URL
  let label: String
  @State private var player: AVPlayer?

  var body: some View {
    VideoPlayer(player: player)
      .accessibilityLabel(Text(label))
      .onAppear { if player == nil { player = AVPlayer(url: url) } }
      .onDisappear { player?.pause() }
  }
}

/// Audio, like `<audio preload="none" controls>`: nothing loads until the viewer presses play.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridAudioView: View {
  let url: URL
  let label: String
  @State private var player: AVPlayer?

  var body: some View {
    Group {
      if let player {
        VideoPlayer(player: player)
      } else {
        Button {
          let player = AVPlayer(url: url)
          self.player = player
          player.play()
        } label: {
          Label(label, systemImage: "play.circle.fill")
            .labelStyle(.iconOnly)
            .font(.system(size: 28))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
      }
    }
    .onDisappear { player?.pause() }
  }
}

/// Default embed rendering: no third-party request until the viewer chooses to open the video.
/// Supply `embed:` on `GridView` to show a consent-aware inline player instead.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridEmbedCard: View {
  let node: GridBuiltinNode
  let messages: GridMessages

  var body: some View {
    if let embed = GridEmbed(node.url), let url = URL(string: embed.pageURL) {
      let provider = embed.provider == .youtube ? "YouTube" : "Vimeo"
      GridLinkButton(url: url) {
        VStack(spacing: 8) {
          Image(systemName: "play.rectangle.fill").font(.system(size: 28))
          Text(node.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
          Text(String(format: messages.openEmbed, provider)).font(.system(size: 12, weight: .medium)).opacity(0.7)
        }
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.06))
        .contentShape(Rectangle())
      }
      .accessibilityLabel(Text(node.name))
      .accessibilityHint(Text(String(format: messages.openEmbed, provider)))
    } else if let href = GridURL.safeHref(node.url), let url = URL(string: href) {
      GridLinkButton(url: url) { Text(node.name).underline() }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      GridPlaceholder(text: (node.url?.isEmpty == false ? node.url : nil) ?? node.name)
    }
  }
}

/// Opens a safe http(s) URL through the environment's `openURL`, so hosts can intercept it.
/// A plain button (rather than `Link`) also renders in `ImageRenderer` snapshots.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridLinkButton<Label: View>: View {
  let url: URL
  @ViewBuilder var label: Label
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button { openURL(url) } label: { label }
      .buttonStyle(.plain)
      .accessibilityAddTraits(.isLink)
      .accessibilityRemoveTraits(.isButton)
  }
}
