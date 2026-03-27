import AppKit

/// Centralized visual constants for the subtitle overlay panel.
/// All values match the decisions documented in 02-CONTEXT.md.
/// @MainActor because NSFont/NSColor are not Sendable and all
/// consumers (SubtitlePanel) run on the main thread.
@MainActor
enum SubtitleStyle {

    // MARK: - Colors

    /// Gold #FFD700 — highlights the currently spoken word
    static let currentWordColor = NSColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0)

    /// Silver-grey #A0A0A0 — already-spoken words
    static let pastWordColor = NSColor(red: 0.627, green: 0.627, blue: 0.627, alpha: 1.0)

    /// White #FFFFFF — words not yet spoken
    static let futureWordColor = NSColor.white

    /// Black at 30% opacity — panel background
    static let backgroundColor = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.3)

    // MARK: - Fonts

    /// Bold font for the current word (default medium; use dynamicCurrentWordFont for settings-aware)
    static let currentWordFont = font(size: FontSize.medium.rawValue, weight: .bold)

    /// Regular font for past and future words (default medium; use dynamicRegularFont for settings-aware)
    static let regularFont = font(size: FontSize.medium.rawValue, weight: .regular)

    /// Font size presets (SwiftBar configurable: S/M/L)
    enum FontSize: CGFloat {
        case small = 22
        case medium = 28
        case large = 36
    }

    /// Resolve a settings string ("small", "medium", "large") to a FontSize enum value.
    static func resolvedFontSize(_ name: String) -> FontSize {
        switch name.lowercased() {
        case "small": return .small
        case "large": return .large
        default: return .medium
        }
    }

    /// Bold font for the current word, sized according to the settings string.
    static func dynamicCurrentWordFont(_ sizeName: String) -> NSFont {
        font(size: resolvedFontSize(sizeName).rawValue, weight: .bold)
    }

    /// Regular font for past/future words, sized according to the settings string.
    static func dynamicRegularFont(_ sizeName: String) -> NSFont {
        font(size: resolvedFontSize(sizeName).rawValue, weight: .regular)
    }

    /// Create a font using SF Pro Display if available, falling back to system font.
    static func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont(name: "SF Pro Display", size: size).map {
            NSFontManager.shared.convert(
                $0, toHaveTrait: weight == .bold ? .boldFontMask : .unboldFontMask
            )
        } ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    // MARK: - Layout

    /// Corner radius for the panel background
    static let cornerRadius: CGFloat = 10

    /// Horizontal padding inside the panel
    static let horizontalPadding: CGFloat = 16

    /// Vertical padding inside the panel
    static let verticalPadding: CGFloat = 12

    /// Distance from the bottom edge of the screen
    static let bottomOffset: CGFloat = 80

    /// Distance from the top edge of the screen (menu bar area)
    static let topOffset: CGFloat = 80

    /// Panel width as a fraction of screen width (70%)
    static let widthRatio: CGFloat = 0.9

    /// Maximum number of text lines before clipping
    static let maxLines = 2

    /// Seconds to keep the last subtitle visible after the final word
    static let lingerDuration: TimeInterval = 2.0

    /// Safety fallback: truncate text that overflows the 2-line display
    static let truncatesLastVisibleLine = true
}
