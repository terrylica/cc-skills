// Animated rainbow gradient border for the subtitle panel.
// Supports zigzag edge indicators for bisected paragraph continuation.
import AppKit

/// Creates and manages an animated rainbow gradient border on a layer.
/// Zigzag continuation indicators are rendered as separate overlay strips
/// to avoid distorting the main border path.
@MainActor
public final class SubtitleBorder {

    /// Describes which edges should show zigzag continuation indicators.
    public struct EdgeHint: Sendable, Equatable {
        public let jaggedTop: Bool
        public let jaggedBottom: Bool

        public static let none = EdgeHint(jaggedTop: false, jaggedBottom: false)

        public init(jaggedTop: Bool, jaggedBottom: Bool) {
            self.jaggedTop = jaggedTop
            self.jaggedBottom = jaggedBottom
        }
    }

    // Main border (always smooth rounded rect)
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()

    // Zigzag indicator strips (independent overlay layers)
    private let topZigzag = CAShapeLayer()
    private let bottomZigzag = CAShapeLayer()
    private var currentEdgeHint: EdgeHint = .none
    private weak var hostLayer: CALayer?

    /// Attach the rainbow border to a host view's layer.
    func attach(to hostLayer: CALayer, cornerRadius: CGFloat) {
        self.hostLayer = hostLayer

        gradientLayer.colors = Self.rainbowColors
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerRadius = cornerRadius

        maskLayer.lineWidth = 3.0
        maskLayer.fillColor = nil
        maskLayer.strokeColor = NSColor.white.cgColor
        gradientLayer.mask = maskLayer

        hostLayer.addSublayer(gradientLayer)

        // Configure zigzag indicator strips (hidden by default)
        for strip in [topZigzag, bottomZigzag] {
            strip.fillColor = nil
            strip.strokeColor = nil
            strip.lineWidth = 2.0
            strip.isHidden = true
            hostLayer.addSublayer(strip)
        }

        // Animate color cycling on main border
        let animation = CABasicAnimation(keyPath: "colors")
        animation.toValue = Self.rainbowColorsShifted
        animation.duration = 3.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        gradientLayer.add(animation, forKey: "rainbowShift")
    }

    /// Update border frame to match the host view's bounds (call after resize).
    func updateFrame(bounds: CGRect, cornerRadius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        maskLayer.path = buildBorderMask(bounds: bounds, cornerRadius: cornerRadius)
        updateZigzagStrips(bounds: bounds, cornerRadius: cornerRadius)
        CATransaction.commit()
    }

    /// Update which edges show zigzag indicators.
    func setEdgeHint(_ hint: EdgeHint, bounds: CGRect) {
        guard hint != currentEdgeHint else { return }
        currentEdgeHint = hint
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Rebuild border mask with gaps where zigzag replaces straight edges
        maskLayer.path = buildBorderMask(bounds: bounds, cornerRadius: gradientLayer.cornerRadius)
        updateZigzagStrips(bounds: bounds, cornerRadius: gradientLayer.cornerRadius)
        CATransaction.commit()
    }

    /// Reset edges to normal (hide all zigzag indicators).
    func clearEdgeHint(bounds: CGRect) {
        setEdgeHint(.none, bounds: bounds)
    }

    // MARK: - Border Mask (gaps for zigzag edges)

    /// Build the border stroke mask. When zigzag is active on an edge,
    /// that edge segment is omitted from the mask so the zigzag strip shows through.
    private func buildBorderMask(bounds: CGRect, cornerRadius: CGFloat) -> CGPath {
        guard currentEdgeHint.jaggedTop || currentEdgeHint.jaggedBottom else {
            return CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        }

        let r = cornerRadius
        let path = CGMutablePath()

        // Draw border as individual segments, skipping edges that have zigzag.
        // Left edge + corners (always drawn)
        path.move(to: CGPoint(x: 0, y: bounds.height - r))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)

        if !currentEdgeHint.jaggedTop {
            // Top edge: draw straight
            path.addLine(to: CGPoint(x: bounds.width - r, y: 0))
        } else {
            // Top edge: skip (move without drawing)
            path.move(to: CGPoint(x: bounds.width - r, y: 0))
        }

        // Top-right corner + right edge (always drawn)
        path.addArc(tangent1End: CGPoint(x: bounds.width, y: 0), tangent2End: CGPoint(x: bounds.width, y: r), radius: r)
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height - r))

        if !currentEdgeHint.jaggedBottom {
            // Bottom edge: draw straight
            path.addArc(tangent1End: CGPoint(x: bounds.width, y: bounds.height), tangent2End: CGPoint(x: bounds.width - r, y: bounds.height), radius: r)
            path.addLine(to: CGPoint(x: r, y: bounds.height))
            path.addArc(tangent1End: CGPoint(x: 0, y: bounds.height), tangent2End: CGPoint(x: 0, y: bounds.height - r), radius: r)
        } else {
            // Bottom edge: draw corners only, skip straight segment
            path.addArc(tangent1End: CGPoint(x: bounds.width, y: bounds.height), tangent2End: CGPoint(x: bounds.width - r, y: bounds.height), radius: r)
            path.move(to: CGPoint(x: r, y: bounds.height))
            path.addArc(tangent1End: CGPoint(x: 0, y: bounds.height), tangent2End: CGPoint(x: 0, y: bounds.height - r), radius: r)
        }

        // Close left edge
        path.closeSubpath()
        return path
    }

    // MARK: - Zigzag Strip Rendering

    private func updateZigzagStrips(bounds: CGRect, cornerRadius: CGFloat) {
        let r = cornerRadius
        let tooth: CGFloat = 2.5
        let pitch: CGFloat = 8.0
        let borderWidth: CGFloat = maskLayer.lineWidth

        // Top zigzag strip — sits on the border line position
        if currentEdgeHint.jaggedTop {
            let path = CGMutablePath()
            let y = borderWidth / 2  // center of where the border stroke would be
            path.move(to: CGPoint(x: r, y: y))
            Self.addZigzag(to: path, from: CGPoint(x: r, y: y), to: CGPoint(x: bounds.width - r, y: y), tooth: tooth, pitch: pitch)
            topZigzag.path = path
            topZigzag.frame = bounds
            topZigzag.lineWidth = borderWidth
            topZigzag.strokeColor = NSColor.systemOrange.withAlphaComponent(0.9).cgColor
            topZigzag.isHidden = false
        } else {
            topZigzag.isHidden = true
        }

        // Bottom zigzag strip — sits on the border line position
        if currentEdgeHint.jaggedBottom {
            let path = CGMutablePath()
            let y = bounds.height - borderWidth / 2
            path.move(to: CGPoint(x: r, y: y))
            Self.addZigzag(to: path, from: CGPoint(x: r, y: y), to: CGPoint(x: bounds.width - r, y: y), tooth: tooth, pitch: pitch)
            bottomZigzag.path = path
            bottomZigzag.frame = bounds
            bottomZigzag.lineWidth = borderWidth
            bottomZigzag.strokeColor = NSColor.systemCyan.withAlphaComponent(0.9).cgColor
            bottomZigzag.isHidden = false
        } else {
            bottomZigzag.isHidden = true
        }
    }

    /// Append a zigzag waveform between two horizontal points.
    private static func addZigzag(to path: CGMutablePath, from start: CGPoint, to end: CGPoint, tooth: CGFloat, pitch: CGFloat) {
        let totalDist = abs(end.x - start.x)
        let steps = Int(totalDist / pitch)
        guard steps > 0 else {
            path.addLine(to: end)
            return
        }
        let direction: CGFloat = end.x > start.x ? 1 : -1
        let actualPitch = totalDist / CGFloat(steps)
        for i in 0..<steps {
            let midX = start.x + direction * (CGFloat(i) + 0.5) * actualPitch
            let endX = start.x + direction * CGFloat(i + 1) * actualPitch
            let yOffset: CGFloat = (i % 2 == 0) ? -tooth : tooth
            path.addLine(to: CGPoint(x: midX, y: start.y + yOffset))
            path.addLine(to: CGPoint(x: endX, y: start.y))
        }
    }

    // MARK: - Color Palettes

    static let rainbowColors: [CGColor] = [
        NSColor.systemRed.cgColor,
        NSColor.systemOrange.cgColor,
        NSColor.systemYellow.cgColor,
        NSColor.systemGreen.cgColor,
        NSColor.systemCyan.cgColor,
        NSColor.systemBlue.cgColor,
        NSColor.systemPurple.cgColor,
        NSColor.systemPink.cgColor,
        NSColor.systemRed.cgColor,
    ]

    static let rainbowColorsShifted: [CGColor] = [
        NSColor.systemPurple.cgColor,
        NSColor.systemPink.cgColor,
        NSColor.systemRed.cgColor,
        NSColor.systemOrange.cgColor,
        NSColor.systemYellow.cgColor,
        NSColor.systemGreen.cgColor,
        NSColor.systemCyan.cgColor,
        NSColor.systemBlue.cgColor,
        NSColor.systemPurple.cgColor,
    ]
}
