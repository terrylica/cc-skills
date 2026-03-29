// Animated rainbow gradient border for the subtitle panel.
import AppKit

/// Creates and manages an animated rainbow gradient border on a layer.
@MainActor
public final class SubtitleBorder {

    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()

    /// Attach the rainbow border to a host view's layer.
    func attach(to hostLayer: CALayer, cornerRadius: CGFloat) {
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        maskLayer.path = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        CATransaction.commit()
    }

    // MARK: - Color Palettes

    private static let rainbowColors: [CGColor] = [
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

    private static let rainbowColorsShifted: [CGColor] = [
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
