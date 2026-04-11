// Subtitle panel position persistence and calculation.
// Multi-monitor aware: saves CGDirectDisplayID alongside coordinates,
// validates against currently-connected screens on restore.
import AppKit

/// Manages subtitle panel position: preset positions (top/middle/bottom),
/// user drag persistence, and auto-height measurement.
/// Multi-monitor safe: stores display ID with saved position, validates
/// on restore, falls back to preset if saved screen is disconnected.
@MainActor
public enum SubtitlePosition {

    private static let savedXKey = "subtitlePanelX"
    private static let savedTopYKey = "subtitlePanelTopY"
    private static let savedFlagKey = "subtitlePanelPositionSaved"
    private static let savedDisplayIDKey = "subtitlePanelDisplayID"
    private static let savedScreenHeightKey = "subtitlePanelScreenHeight"

    /// Save the panel's current position (top-left corner relative to its screen).
    /// Stores the display ID and screen height of the screen the panel is on,
    /// so restore can validate the screen is still connected and convert coordinates correctly.
    static func save(frame: NSRect, on screen: NSScreen?) {
        let targetScreen = screen ?? screenContaining(frame: frame) ?? NSScreen.screens.first
        guard let targetScreen else { return }

        let screenHeight = targetScreen.frame.height
        let topLeftY = screenHeight - (frame.origin.y + frame.height)

        UserDefaults.standard.set(frame.origin.x, forKey: savedXKey)
        UserDefaults.standard.set(topLeftY, forKey: savedTopYKey)
        UserDefaults.standard.set(true, forKey: savedFlagKey)
        UserDefaults.standard.set(screenHeight, forKey: savedScreenHeightKey)

        if let displayID = targetScreen.displayID {
            UserDefaults.standard.set(Int(displayID), forKey: savedDisplayIDKey)
        }
    }

    /// Clear saved position (used when user selects a preset via HTTP API
    /// or when the saved screen is no longer connected).
    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: savedXKey)
        UserDefaults.standard.removeObject(forKey: savedTopYKey)
        UserDefaults.standard.removeObject(forKey: savedDisplayIDKey)
        UserDefaults.standard.removeObject(forKey: savedScreenHeightKey)
        UserDefaults.standard.set(false, forKey: savedFlagKey)
    }

    /// Calculate the panel frame, restoring saved position if available
    /// and the saved screen is still connected.
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

            // Validate saved display is still connected
            let savedDisplayID = UserDefaults.standard.integer(forKey: savedDisplayIDKey)
            if savedDisplayID != 0 && !isDisplayConnected(CGDirectDisplayID(savedDisplayID)) {
                // Saved screen disconnected — fall back to preset
                clearSaved()
                return calculatePresetFrame(
                    panelWidth: panelWidth, panelHeight: panelHeight,
                    screenFrame: screenFrame, screenFullFrame: screenFullFrame,
                    preset: preset
                )
            }

            // Use the screen height that was saved (not NSScreen.main which follows mouse)
            let screenHeight = UserDefaults.standard.double(forKey: savedScreenHeightKey)
            let effectiveHeight = screenHeight > 0 ? screenHeight : screenFullFrame.height

            x = savedX
            y = effectiveHeight - savedTopY - panelHeight

            // Validate the restored position is on a currently-connected screen
            let restoredCenter = NSPoint(x: x + panelWidth / 2, y: y + panelHeight / 2)
            if screenContaining(point: restoredCenter) == nil {
                clearSaved()
                return calculatePresetFrame(
                    panelWidth: panelWidth, panelHeight: panelHeight,
                    screenFrame: screenFrame, screenFullFrame: screenFullFrame,
                    preset: preset
                )
            }
        } else {
            return calculatePresetFrame(
                panelWidth: panelWidth, panelHeight: panelHeight,
                screenFrame: screenFrame, screenFullFrame: screenFullFrame,
                preset: preset
            )
        }

        return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    /// Calculate frame from preset position (no saved drag position).
    private static func calculatePresetFrame(
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        screenFrame: NSRect,
        screenFullFrame: NSRect,
        preset: String
    ) -> NSRect {
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y: CGFloat
        switch preset {
        case "top":
            y = screenFrame.origin.y + screenFrame.height - panelHeight - SubtitleStyle.topOffset
        case "middle":
            y = screenFrame.origin.y + (screenFrame.height - panelHeight) / 2
        default: // bottom
            y = screenFullFrame.origin.y + SubtitleStyle.bottomOffset
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

    // MARK: - Screen Utilities

    /// Check if a display ID corresponds to a currently-connected screen.
    static func isDisplayConnected(_ displayID: CGDirectDisplayID) -> Bool {
        NSScreen.screens.contains { $0.displayID == displayID }
    }

    /// Find the screen containing a given point.
    static func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// Find the screen containing the center of a given frame.
    static func screenContaining(frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return screenContaining(point: center)
    }
}

// MARK: - NSScreen Display ID Extension

public extension NSScreen {
    /// The CGDirectDisplayID for this screen, extracted from deviceDescription.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
