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
        maskLayer.path = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        updateZigzagStrips(bounds: bounds, cornerRadius: cornerRadius)
        CATransaction.commit()
    }

    /// Update which edges show zigzag indicators.
    func setEdgeHint(_ hint: EdgeHint, bounds: CGRect) {
        guard hint != currentEdgeHint else { return }
        currentEdgeHint = hint
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateZigzagStrips(bounds: bounds, cornerRadius: gradientLayer.cornerRadius)
        CATransaction.commit()
    }

    /// Reset edges to normal (hide all zigzag indicators).
    func clearEdgeHint(bounds: CGRect) {
        setEdgeHint(.none, bounds: bounds)
    }

    // MARK: - Zigzag Strip Rendering

    private func updateZigzagStrips(bounds: CGRect, cornerRadius: CGFloat) {
        let r = cornerRadius
        let tooth: CGFloat = 2.5
        let pitch: CGFloat = 8.0

        // Top zigzag strip
        if currentEdgeHint.jaggedTop {
            let path = CGMutablePath()
            let y: CGFloat = 1.5  // just inside the border
            path.move(to: CGPoint(x: r, y: y))
            Self.addZigzag(to: path, from: CGPoint(x: r, y: y), to: CGPoint(x: bounds.width - r, y: y), tooth: tooth, pitch: pitch)
            topZigzag.path = path
            topZigzag.frame = bounds
            topZigzag.strokeColor = NSColor.systemOrange.withAlphaComponent(0.8).cgColor
            topZigzag.isHidden = false
        } else {
            topZigzag.isHidden = true
        }

        // Bottom zigzag strip
        if currentEdgeHint.jaggedBottom {
            let path = CGMutablePath()
            let y = bounds.height - 1.5  // just inside the border
            path.move(to: CGPoint(x: r, y: y))
            Self.addZigzag(to: path, from: CGPoint(x: r, y: y), to: CGPoint(x: bounds.width - r, y: y), tooth: tooth, pitch: pitch)
            bottomZigzag.path = path
            bottomZigzag.frame = bounds
            bottomZigzag.strokeColor = NSColor.systemCyan.withAlphaComponent(0.8).cgColor
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
