import CoreText
import Foundation
import NullDullGrid
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Host colours used where a document says `transparent` (the theme). Authored colours never change.
@available(iOS 16, macOS 13, tvOS 16, *)
public struct GridTheme: Sendable {
  /// Defaults to `.primary`, which follows light and dark mode.
  public var foreground: Color?
  /// Defaults to no fill.
  public var background: Color?
  public init(foreground: Color? = nil, background: Color? = nil) {
    self.foreground = foreground
    self.background = background
  }
}

/// Fallback strings shown by the renderer. Localize them in the host app.
@available(iOS 16, macOS 13, tvOS 16, *)
public struct GridMessages: Sendable {
  public var unavailable: String
  public var download: String
  public var chooseAsset: String
  /// Label of the tvOS embed card, which opens the video on the provider, e.g. "Open on YouTube".
  /// `%@` is the provider name.
  public var openEmbed: String
  /// Accessibility label prefix of the embed poster's play button in `.tap` loading, followed by the node name.
  public var play: String
  public init(
    unavailable: String = "Preview unavailable.", download: String = "Download original",
    chooseAsset: String = "No asset selected", openEmbed: String = "Open on %@", play: String = "Play"
  ) {
    self.unavailable = unavailable
    self.download = download
    self.chooseAsset = chooseAsset
    self.openEmbed = openEmbed
    self.play = play
  }
}

/// Where Dynamic Type may resize authored text.
@available(iOS 16, macOS 13, tvOS 16, *)
public enum GridDynamicType: Sendable {
  /// Scale text that sizes its own box: flowing text in content-flow layouts. Fixed canvases keep
  /// authored sizes, because their frames do not grow with text. Default.
  case contentFlowText
  /// Always use authored sizes.
  case never
}

@available(iOS 16, macOS 13, tvOS 16, *)
extension GridColor {
  var swiftUI: Color? {
    guard let rgb else { return nil }
    return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
  }
}

@available(iOS 16, macOS 13, tvOS 16, *)
extension GridRGBA {
  var swiftUI: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// `themeColor`: transparent (or absent) means "use the fallback".
@available(iOS 16, macOS 13, tvOS 16, *)
func themeColor(_ value: GridColor?, _ fallback: Color) -> Color {
  value?.swiftUI ?? fallback
}

/// `colorWithOpacity`: per-colour opacity that does not dim the node's other layers.
@available(iOS 16, macOS 13, tvOS 16, *)
func withOpacity(_ color: Color, _ opacity: Double?) -> Color {
  guard let opacity, opacity != 1 else { return color }
  return color.opacity(opacity)
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct GridForegroundKey: EnvironmentKey {
  static let defaultValue: Color = .primary
}

@available(iOS 16, macOS 13, tvOS 16, *)
extension EnvironmentValues {
  /// The active layout's foreground: the theme or layout colour, with the layout's colour opacity.
  var gridForeground: Color {
    get { self[GridForegroundKey.self] }
    set { self[GridForegroundKey.self] = newValue }
  }
}

/// Fonts matching the web renderer's families on Apple platforms.
@available(iOS 16, macOS 13, tvOS 16, *)
enum GridFonts {
  static func base(_ family: GridFontFamily, size: CGFloat, descriptor: CTFontDescriptor?) -> CTFont {
    if let descriptor { return CTFontCreateWithFontDescriptor(descriptor, size, nil) }
    switch family {
    case .system, .sans:
      return CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    case .rounded:
      let system = CTFontCreateUIFontForLanguage(.system, size, nil)!
      #if canImport(UIKit)
        if let rounded = (system as UIFont).fontDescriptor.withDesign(.rounded) {
          return UIFont(descriptor: rounded, size: size) as CTFont
        }
      #else
        if let rounded = (system as NSFont).fontDescriptor.withDesign(.rounded),
          let font = NSFont(descriptor: rounded, size: size)
        {
          return font as CTFont
        }
      #endif
      return system
    case .serif:
      // The web renderer asks for Georgia, which ships with iOS and macOS.
      let georgia = CTFontCreateWithName("Georgia" as CFString, size, nil)
      if (CTFontCopyFamilyName(georgia) as String) == "Georgia" { return georgia }
      let system = CTFontCreateUIFontForLanguage(.system, size, nil)!
      #if canImport(UIKit)
        if let serif = (system as UIFont).fontDescriptor.withDesign(.serif) {
          return UIFont(descriptor: serif, size: size) as CTFont
        }
      #endif
      return system
    case .mono:
      #if canImport(UIKit)
        return UIFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
      #else
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
      #endif
    }
  }

  static func variant(_ font: CTFont, bold: Bool, italic: Bool, mono: Bool) -> CTFont {
    var result = font
    if mono {
      #if canImport(UIKit)
        result = UIFont.monospacedSystemFont(ofSize: CTFontGetSize(font), weight: .regular) as CTFont
      #else
        result = NSFont.monospacedSystemFont(ofSize: CTFontGetSize(font), weight: .regular) as CTFont
      #endif
    }
    var traits: CTFontSymbolicTraits = []
    if bold { traits.insert(.traitBold) }
    if italic { traits.insert(.traitItalic) }
    if !traits.isEmpty, let copy = CTFontCreateCopyWithSymbolicTraits(result, 0, nil, traits, traits) {
      result = copy
    } else if bold, let copy = CTFontCreateCopyWithSymbolicTraits(result, 0, nil, .traitBold, .traitBold) {
      result = copy
    }
    return result
  }

  /// The line height a SwiftUI `Text` uses for this font before `lineSpacing`.
  static func naturalLineHeight(_ font: CTFont) -> CGFloat {
    #if canImport(UIKit)
      return (font as UIFont).lineHeight
    #else
      return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    #endif
  }
}

/// Scales authored point sizes for Dynamic Type.
@available(iOS 16, macOS 13, tvOS 16, *)
enum GridTypeScale {
  static func factor(_ size: DynamicTypeSize) -> CGFloat {
    #if canImport(UIKit) && !os(watchOS)
      let category: UIContentSizeCategory
      switch size {
      case .xSmall: category = .extraSmall
      case .small: category = .small
      case .medium: category = .medium
      case .large: category = .large
      case .xLarge: category = .extraLarge
      case .xxLarge: category = .extraExtraLarge
      case .xxxLarge: category = .extraExtraExtraLarge
      case .accessibility1: category = .accessibilityMedium
      case .accessibility2: category = .accessibilityLarge
      case .accessibility3: category = .accessibilityExtraLarge
      case .accessibility4: category = .accessibilityExtraExtraLarge
      case .accessibility5: category = .accessibilityExtraExtraExtraLarge
      @unknown default: category = .large
      }
      let traits = UITraitCollection(preferredContentSizeCategory: category)
      return UIFontMetrics(forTextStyle: .body).scaledValue(for: 100, compatibleWith: traits) / 100
    #else
      return 1
    #endif
  }
}
