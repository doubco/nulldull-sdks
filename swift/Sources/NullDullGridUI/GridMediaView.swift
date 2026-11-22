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
