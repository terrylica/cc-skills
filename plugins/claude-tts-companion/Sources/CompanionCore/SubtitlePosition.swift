// Subtitle panel position persistence and calculation.
import AppKit

/// Manages subtitle panel position: preset positions (top/middle/bottom),
/// user drag persistence, and auto-height measurement.
@MainActor
public enum SubtitlePosition {

    private static let savedXKey = "subtitlePanelX"
    private static let savedTopYKey = "subtitlePanelTopY"
    private static let savedFlagKey = "subtitlePanelPositionSaved"

    /// Save the panel's current position (top-left corner relative to screen).
    static func save(frame: NSRect) {
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let topLeftY = screenHeight - (frame.origin.y + frame.height)
        UserDefaults.standard.set(frame.origin.x, forKey: savedXKey)
        UserDefaults.standard.set(topLeftY, forKey: savedTopYKey)
        UserDefaults.standard.set(true, forKey: savedFlagKey)
    }

    /// Clear saved position (used when user selects a preset via SwiftBar).
    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: savedXKey)
        UserDefaults.standard.removeObject(forKey: savedTopYKey)
        UserDefaults.standard.set(false, forKey: savedFlagKey)
    }

    /// Calculate the panel frame, restoring saved position if available.
    static func calculateFrame(
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        screenFrame: NSRect,
        screenFullFrame: NSRect,
        preset: String
    ) -> NSRect {
        let hasSaved = UserDefaults.standard.bool(forKey: savedFlagKey)

        let x: CGFloat
        let y: CGFloat

        if hasSaved {
            let savedX = UserDefaults.standard.double(forKey: savedXKey)
            let savedTopY = UserDefaults.standard.double(forKey: savedTopYKey)
            let screenHeight = NSScreen.main?.frame.height ?? screenFrame.height
            x = savedX
            y = screenHeight - savedTopY - panelHeight
        } else {
            x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
            switch preset {
            case "top":
                y = screenFrame.origin.y + screenFrame.height - panelHeight - SubtitleStyle.topOffset
            case "middle":
                y = screenFrame.origin.y + (screenFrame.height - panelHeight) / 2
            default: // bottom
                y = screenFullFrame.origin.y + SubtitleStyle.bottomOffset
            }
        }

        return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    /// Measure required panel height for current text content.
    static func measureHeight(
        textField: NSTextField,
        font: NSFont,
        textWidth: CGFloat,
        screenHeight: CGFloat
    ) -> CGFloat {
        let lineHeight = ceil(font.ascender - font.descender + font.leading)

        let measuredHeight: CGFloat
        if let cell = textField.cell, textField.attributedStringValue.length > 0 {
            let cellSize = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: CGFloat.greatestFiniteMagnitude))
            measuredHeight = max(lineHeight * 2, ceil(cellSize.height))
        } else {
            measuredHeight = lineHeight * 2
        }

        // Cap at 60% of screen height
        let maxHeight = screenHeight * 0.6
        return min(measuredHeight + SubtitleStyle.verticalPadding * 2, maxHeight)
    }
}
