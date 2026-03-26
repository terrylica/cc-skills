import AppKit

/// A floating, click-through, screen-sharing-invisible subtitle overlay panel.
///
/// Positioned at the bottom center of the main display, this panel shows
/// up to 2 lines of word-wrapped text with karaoke-style highlighting.
/// All UI operations must occur on the main thread.
@MainActor
final class SubtitlePanel: NSPanel {

    // MARK: - Subviews

    /// Background container with rounded corners and translucent fill.
    private let backgroundView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// The label that displays subtitle text (plain or attributed).
    private let textField: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = SubtitleStyle.futureWordColor
        field.font = SubtitleStyle.regularFont
        field.alignment = .center
        field.maximumNumberOfLines = SubtitleStyle.maxLines
        field.cell?.isScrollable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    // MARK: - Initialization

    init() {
        // Use a placeholder frame; positionOnScreen() sets the real one.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureWindowBehavior()
        configureContentView()
        positionOnScreen()
    }

    // MARK: - Focus Prevention (SUB-09)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Public API

    /// Show plain text in the subtitle panel (white, regular weight).
    func show(text: String) {
        textField.stringValue = text
        positionOnScreen()
        orderFrontRegardless()
    }

    /// Hide the subtitle panel.
    func hide() {
        orderOut(nil)
    }

    /// Show attributed text for karaoke highlighting (gold/grey/white per word).
    func updateAttributedText(_ text: NSAttributedString) {
        textField.attributedStringValue = text
        positionOnScreen()
        orderFrontRegardless()
    }

    // MARK: - Private Helpers

    /// Configure all NSPanel window-behavior flags.
    private func configureWindowBehavior() {
        // SUB-01: Always on top
        level = .floating

        // SUB-11: Visible on all Spaces and over fullscreen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // SUB-08: Invisible to screen sharing / screenshots
        sharingType = .none

        // SUB-10: Click-through — mouse events pass to windows below
        ignoresMouseEvents = true

        // Transparent chrome
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    /// Build the view hierarchy: background view + centered text field.
    private func configureContentView() {
        guard let content = contentView else { return }

        // Background with rounded corners and translucent fill
        content.addSubview(backgroundView)
        backgroundView.layer?.backgroundColor = SubtitleStyle.backgroundColor.cgColor
        backgroundView.layer?.cornerRadius = SubtitleStyle.cornerRadius
        backgroundView.layer?.masksToBounds = true

        // Pin background to fill the content view
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: content.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Text field inside background with padding
        backgroundView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(
                equalTo: backgroundView.leadingAnchor,
                constant: SubtitleStyle.horizontalPadding
            ),
            textField.trailingAnchor.constraint(
                equalTo: backgroundView.trailingAnchor,
                constant: -SubtitleStyle.horizontalPadding
            ),
            textField.topAnchor.constraint(
                equalTo: backgroundView.topAnchor,
                constant: SubtitleStyle.verticalPadding
            ),
            textField.bottomAnchor.constraint(
                equalTo: backgroundView.bottomAnchor,
                constant: -SubtitleStyle.verticalPadding
            ),
        ])
    }

    /// Position the panel at bottom center of the main screen (SUB-02).
    func positionOnScreen() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelWidth = screenFrame.width * SubtitleStyle.widthRatio

        // Height is driven by Auto Layout (text field intrinsic size + padding).
        // Use a reasonable minimum that fits 2 lines at 28pt + vertical padding.
        let lineHeight = SubtitleStyle.regularFont.boundingRectForFont.height
        let panelHeight = lineHeight * CGFloat(SubtitleStyle.maxLines)
            + SubtitleStyle.verticalPadding * 2

        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screen.frame.origin.y + SubtitleStyle.bottomOffset

        let frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        setFrame(frame, display: true)
    }
}
