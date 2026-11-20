import CoreText
import Foundation
import NullDullGrid
import SwiftUI

#if canImport(UIKit)
  import UIKit
  public typealias GridPlatformImage = UIImage
#elseif canImport(AppKit)
  import AppKit
  public typealias GridPlatformImage = NSImage
#endif

@available(iOS 16, macOS 13, tvOS 16, *)
extension Image {
  init(gridImage: GridPlatformImage) {
    #if canImport(UIKit)
      self.init(uiImage: gridImage)
    #else
      self.init(nsImage: gridImage)
    #endif
  }
}

/// Fetches asset bytes. Replace it to add caching, authentication-free proxies or test data.
@available(iOS 16, macOS 13, tvOS 16, *)
public protocol GridAssetLoading: Sendable {
  /// Returns at most `maxBytes` bytes or throws.
  func data(for url: URL, maxBytes: Int) async throws -> Data
}

@available(iOS 16, macOS 13, tvOS 16, *)
public struct GridAssetTooLarge: Error {}

/// Loads assets with `URLSession`: no cookies, no redirects to other schemes, bounded size.
@available(iOS 16, macOS 13, tvOS 16, *)
public struct URLSessionGridAssetLoader: GridAssetLoading {
  public let session: URLSession
  public init(session: URLSession = .shared) { self.session = session }

  public func data(for url: URL, maxBytes: Int) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpShouldHandleCookies = false
    request.timeoutInterval = 15
    if maxBytes > 4 * 1024 * 1024 {
      let (data, response) = try await session.data(for: request)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw URLError(.badServerResponse)
      }
      guard data.count <= maxBytes else { throw GridAssetTooLarge() }
      return data
    }
    // Small budgets (fonts, SVG) stop reading as soon as the limit is passed.
    let (bytes, response) = try await session.bytes(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw URLError(.badServerResponse)
    }
    if response.expectedContentLength > Int64(maxBytes) { throw GridAssetTooLarge() }
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count > maxBytes { throw GridAssetTooLarge() }
    }
    return data
  }
}

/// Decoded assets shared by every renderer that uses the same store.
///
/// Images and SVG drawings are cached by URL (version your asset URLs). Uploaded fonts
/// are limited to 2 MiB each, at most two download at once, and the cache keeps 32
/// fonts. Failed loads are forgotten so a later appearance can retry.
@available(iOS 16, macOS 13, tvOS 16, *)
@MainActor
public final class GridAssetStore: ObservableObject {
  public static let shared = GridAssetStore()

  public var loader: GridAssetLoading
  @Published private(set) var revision = 0

  private var images: [URL: GridPlatformImage] = [:]
  private var drawings: [URL: Result<GridSVGDrawing, GridSVGRenderError>] = [:]
  private var fonts: [URL: CTFontDescriptor] = [:]
  private var fontOrder: [URL] = []
  private var inFlight: Set<URL> = []
  private var fontSlots = 2
  private var fontQueue: [CheckedContinuation<Void, Never>] = []

  public init(loader: GridAssetLoading = URLSessionGridAssetLoader()) {
    self.loader = loader
  }

  // MARK: Synchronous reads (render path)

  func image(_ url: URL) -> GridPlatformImage? { images[url] }
  func drawing(_ url: URL) -> Result<GridSVGDrawing, GridSVGRenderError>? { drawings[url] }
  func font(_ url: URL) -> CTFontDescriptor? { fonts[url] }

  // MARK: Preloading

  /// Decodes and caches bytes you already have (bundled previews, snapshot tests).
  public func preload(_ data: Data, for url: URL, as kind: Kind) {
    switch kind {
    case .image:
      if let image = GridPlatformImage(data: data) { images[url] = image }
    case .svg:
      drawings[url] = Self.decodeSVG(data)
    case .font:
      if let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData) { storeFont(descriptor, url) }
    }
    revision += 1
  }

  public enum Kind: Sendable { case image, svg, font }

  // MARK: Loading

  func loadImage(_ url: URL) async {
    guard images[url] == nil, inFlight.insert(url).inserted else { return }
    defer { inFlight.remove(url) }
    guard let data = try? await loader.data(for: url, maxBytes: 10 * 1024 * 1024),
      let image = GridPlatformImage(data: data)
    else { return }
    images[url] = image
    revision += 1
  }

  func loadSVG(_ url: URL) async {
    guard drawings[url] == nil, inFlight.insert(url).inserted else { return }
    defer { inFlight.remove(url) }
    do {
      // Public SVGs over 1 MiB are served only as downloads; they are never parsed.
      let data = try await loader.data(for: url, maxBytes: GridLimits.svgMaxBytes)
      drawings[url] = Self.decodeSVG(data)
    } catch {
      drawings[url] = .failure(.unsafe)
    }
    revision += 1
  }

  func loadFont(_ url: URL) async {
    guard fonts[url] == nil, inFlight.insert(url).inserted else { return }
    defer { inFlight.remove(url) }
    await acquireFontSlot()
    defer { releaseFontSlot() }
    if Task.isCancelled { return }
    guard let data = try? await loader.data(for: url, maxBytes: GridLimits.fontMaxBytes),
      let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData)
    else { return }
    storeFont(descriptor, url)
    revision += 1
  }

  private func storeFont(_ descriptor: CTFontDescriptor, _ url: URL) {
    fonts[url] = descriptor
    fontOrder.removeAll { $0 == url }
    fontOrder.append(url)
    while fontOrder.count > 32 { fonts[fontOrder.removeFirst()] = nil }
  }

  private func acquireFontSlot() async {
    if fontSlots > 0 {
      fontSlots -= 1
      return
    }
    await withCheckedContinuation { fontQueue.append($0) }
  }

  private func releaseFontSlot() {
    if fontQueue.isEmpty { fontSlots += 1 } else { fontQueue.removeFirst().resume() }
  }

  nonisolated static func decodeSVG(_ data: Data) -> Result<GridSVGDrawing, GridSVGRenderError> {
    guard data.count <= GridLimits.svgMaxBytes, let text = String(data: data, encoding: .utf8) else {
      return .failure(.unsafe)
    }
    do { return .success(try GridSVG.drawing(text)) } catch let error as GridSVGRenderError {
      return .failure(error)
    } catch {
      return .failure(.unsafe)
    }
  }
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct GridAssetStoreKey: EnvironmentKey {
  static var defaultValue: GridAssetStore { MainActor.assumeIsolated { GridAssetStore.shared } }
}

@available(iOS 16, macOS 13, tvOS 16, *)
extension EnvironmentValues {
  /// The asset store renderers use; defaults to `GridAssetStore.shared`.
  public var gridAssetStore: GridAssetStore {
    get { self[GridAssetStoreKey.self] }
    set { self[GridAssetStoreKey.self] = newValue }
  }
}

@available(iOS 16, macOS 13, tvOS 16, *)
extension View {
  public func gridAssetStore(_ store: GridAssetStore) -> some View {
    environment(\.gridAssetStore, store)
  }
}
