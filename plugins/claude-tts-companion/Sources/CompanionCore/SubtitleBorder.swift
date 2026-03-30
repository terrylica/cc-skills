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

        // Configure zigzag indicator strips (added/removed dynamically per edge hint)
        for strip in [topZigzag, bottomZigzag] {
            strip.fillColor = nil
            strip.strokeColor = nil
            strip.lineWidth = 2.0
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
        currentEdgeHint = .none
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topZigzag.isHidden = true
        topZigzag.path = nil
        bottomZigzag.isHidden = true
        bottomZigzag.path = nil
        maskLayer.path = buildBorderMask(bounds: bounds, cornerRadius: gradientLayer.cornerRadius)
        CATransaction.commit()
    }

    // MARK: - Border Mask (gaps for zigzag edges)

    /// Build the border stroke mask. When zigzag is active on an edge,
    /// that edge is omitted so the zigzag strip shows through.
    /// Uses separate subpaths per visible segment — never closeSubpath()
    /// (which would draw a diagonal line across gaps).
    private func buildBorderMask(bounds: CGRect, cornerRadius: CGFloat) -> CGPath {
        guard currentEdgeHint.jaggedTop || currentEdgeHint.jaggedBottom else {
            return CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        }

        let r = cornerRadius
        let path = CGMutablePath()

        // Segment 1: Left edge (bottom-left corner → top-left corner)
        path.move(to: CGPoint(x: 0, y: bounds.height - r))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)

        // Segment 2: Top edge (only if not jagged)
        if !currentEdgeHint.jaggedTop {
            path.addLine(to: CGPoint(x: bounds.width - r, y: 0))
        }

        // Segment 3: Top-right corner + right edge + bottom-right corner
        path.move(to: CGPoint(x: bounds.width - r, y: 0))
        path.addArc(center: CGPoint(x: bounds.width - r, y: r), radius: r, startAngle: .pi * 1.5, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height - r))
        path.addArc(center: CGPoint(x: bounds.width - r, y: bounds.height - r), radius: r, startAngle: 0, endAngle: .pi * 0.5, clockwise: false)

        // Segment 4: Bottom edge (only if not jagged)
        if !currentEdgeHint.jaggedBottom {
            path.addLine(to: CGPoint(x: r, y: bounds.height))
        }

        // Segment 5: Bottom-left corner (connects back to left edge start)
        path.move(to: CGPoint(x: r, y: bounds.height))
        path.addArc(center: CGPoint(x: r, y: bounds.height - r), radius: r, startAngle: .pi * 0.5, endAngle: .pi, clockwise: false)

        return path
    }

    // MARK: - Zigzag Strip Rendering

    private func updateZigzagStrips(bounds: CGRect, cornerRadius: CGFloat) {
        let r = cornerRadius
        let tooth: CGFloat = 2.5
        let pitch: CGFloat = 8.0
        let borderWidth: CGFloat = maskLayer.lineWidth

        // Remove both strips from layer tree first (guarantees no stale visuals)
        topZigzag.removeFromSuperlayer()
        bottomZigzag.removeFromSuperlayer()

        // Top zigzag strip — sits on the border line position
        if currentEdgeHint.jaggedTop, let host = hostLayer {
            let path = CGMutablePath()
            let y = borderWidth / 2
            path.move(to: CGPoint(x: r, y: y))
            Self.addZigzag(to: path, from: CGPoint(x: r, y: y), to: CGPoint(x: bounds.width - r, y: y), tooth: tooth, pitch: pitch)
            topZigzag.path = path
            topZigzag.frame = bounds
            topZigzag.lineWidth = borderWidth
            topZigzag.strokeColor = NSColor.systemOrange.withAlphaComponent(0.9).cgColor
            topZigzag.isHidden = false
            host.addSublayer(topZigzag)
        }

        // Bottom zigzag strip — sits on the border line position
        if currentEdgeHint.jaggedBottom, let host = hostLayer {
            let path = CGMutablePath()
            let y = bounds.height - borderWidth / 2
            path.move(to: CGPoint(x: r, y: y))
            Self.addZigzag(to: path, from: CGPoint(x: r, y: y), to: CGPoint(x: bounds.width - r, y: y), tooth: tooth, pitch: pitch)
            bottomZigzag.path = path
            bottomZigzag.frame = bounds
            bottomZigzag.lineWidth = borderWidth
            bottomZigzag.strokeColor = NSColor.systemCyan.withAlphaComponent(0.9).cgColor
            bottomZigzag.isHidden = false
            host.addSublayer(bottomZigzag)
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
