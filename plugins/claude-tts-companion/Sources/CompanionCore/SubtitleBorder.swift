// Animated rainbow gradient border for the subtitle panel.
// Supports jagged waveform edges for bisected paragraph continuation indicators.
import AppKit

/// Creates and manages an animated rainbow gradient border on a layer.
@MainActor
public final class SubtitleBorder {

    /// Describes which edges should render as jagged waveforms
    /// to indicate bisected paragraph continuation.
    public struct EdgeHint: Sendable, Equatable {
        public let jaggedTop: Bool
        public let jaggedBottom: Bool

        public static let none = EdgeHint(jaggedTop: false, jaggedBottom: false)

        public init(jaggedTop: Bool, jaggedBottom: Bool) {
            self.jaggedTop = jaggedTop
            self.jaggedBottom = jaggedBottom
        }
    }

    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var currentEdgeHint: EdgeHint = .none
    private var currentCornerRadius: CGFloat = 0

    /// Attach the rainbow border to a host view's layer.
    func attach(to hostLayer: CALayer, cornerRadius: CGFloat) {
        currentCornerRadius = cornerRadius
        gradientLayer.colors = Self.rainbowColors
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerRadius = cornerRadius

        maskLayer.lineWidth = 3.0
        maskLayer.fillColor = nil
        maskLayer.strokeColor = NSColor.white.cgColor
        gradientLayer.mask = maskLayer

        hostLayer.addSublayer(gradientLayer)

        // Animate color cycling
        let animation = CABasicAnimation(keyPath: "colors")
        animation.toValue = Self.rainbowColorsShifted
        animation.duration = 3.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        gradientLayer.add(animation, forKey: "rainbowShift")
    }

    /// Update border frame to match the host view's bounds (call after resize).
    func updateFrame(bounds: CGRect, cornerRadius: CGFloat) {
        currentCornerRadius = cornerRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        maskLayer.path = buildBorderPath(bounds: bounds, cornerRadius: cornerRadius, edgeHint: currentEdgeHint)
        CATransaction.commit()
    }

    /// Update which edges render as jagged waveforms.
    func setEdgeHint(_ hint: EdgeHint, bounds: CGRect) {
        guard hint != currentEdgeHint else { return }
        currentEdgeHint = hint
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.path = buildBorderPath(bounds: bounds, cornerRadius: currentCornerRadius, edgeHint: hint)
        CATransaction.commit()
    }

    /// Reset edges to normal (no jagged waveform).
    func clearEdgeHint(bounds: CGRect) {
        setEdgeHint(.none, bounds: bounds)
    }

    // MARK: - Path Builder

    private func buildBorderPath(bounds: CGRect, cornerRadius: CGFloat, edgeHint: EdgeHint) -> CGPath {
        guard edgeHint.jaggedTop || edgeHint.jaggedBottom else {
            // Normal rounded rect border
            return CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        }

        let r = cornerRadius
        let path = CGMutablePath()
        let tooth: CGFloat = 6.0   // zigzag tooth height
        let pitch: CGFloat = 12.0  // zigzag tooth width

        // Start at top-left after corner
        if edgeHint.jaggedTop {
            // Top edge: jagged zigzag
            path.move(to: CGPoint(x: 0, y: r))
            path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
            Self.addZigzag(to: path, from: CGPoint(x: r, y: 0), to: CGPoint(x: bounds.width - r, y: 0), tooth: tooth, pitch: pitch)
            path.addArc(tangent1End: CGPoint(x: bounds.width, y: 0), tangent2End: CGPoint(x: bounds.width, y: r), radius: r)
        } else {
            // Top edge: smooth
            path.move(to: CGPoint(x: 0, y: r))
            path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
            path.addLine(to: CGPoint(x: bounds.width - r, y: 0))
            path.addArc(tangent1End: CGPoint(x: bounds.width, y: 0), tangent2End: CGPoint(x: bounds.width, y: r), radius: r)
        }

        // Right edge: always smooth
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height - r))

        if edgeHint.jaggedBottom {
            // Bottom edge: jagged zigzag (right to left)
            path.addArc(tangent1End: CGPoint(x: bounds.width, y: bounds.height), tangent2End: CGPoint(x: bounds.width - r, y: bounds.height), radius: r)
            Self.addZigzag(to: path, from: CGPoint(x: bounds.width - r, y: bounds.height), to: CGPoint(x: r, y: bounds.height), tooth: tooth, pitch: pitch)
            path.addArc(tangent1End: CGPoint(x: 0, y: bounds.height), tangent2End: CGPoint(x: 0, y: bounds.height - r), radius: r)
        } else {
            // Bottom edge: smooth
            path.addArc(tangent1End: CGPoint(x: bounds.width, y: bounds.height), tangent2End: CGPoint(x: bounds.width - r, y: bounds.height), radius: r)
            path.addLine(to: CGPoint(x: r, y: bounds.height))
            path.addArc(tangent1End: CGPoint(x: 0, y: bounds.height), tangent2End: CGPoint(x: 0, y: bounds.height - r), radius: r)
        }

        // Left edge: always smooth, close path
        path.closeSubpath()
        return path
    }

    /// Append a zigzag waveform between two horizontal points.
    private static func addZigzag(to path: CGMutablePath, from start: CGPoint, to end: CGPoint, tooth: CGFloat, pitch: CGFloat) {
        let dx = end.x - start.x
        let direction: CGFloat = dx > 0 ? 1 : -1
        let totalDist = abs(dx)
        let steps = Int(totalDist / pitch)
        guard steps > 0 else {
            path.addLine(to: end)
            return
        }

        let actualPitch = totalDist / CGFloat(steps)
        for i in 0..<steps {
            let x1 = start.x + direction * (CGFloat(i) + 0.5) * actualPitch
            let x2 = start.x + direction * CGFloat(i + 1) * actualPitch
            let yOffset = (i % 2 == 0) ? -tooth : tooth
            path.addLine(to: CGPoint(x: x1, y: start.y + yOffset))
            path.addLine(to: CGPoint(x: x2, y: start.y))
        }
        path.addLine(to: end)
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
