import AppKit
import Logging

/// A floating, click-through, screen-sharing-invisible subtitle overlay panel.
///
/// Positioned at the bottom center of the main display, this panel shows
/// up to 2 lines of word-wrapped text with karaoke-style highlighting.
/// All UI operations must occur on the main thread.
@MainActor
final class SubtitlePanel: NSPanel {

    private let logger = Logger(label: "subtitle-panel")

    // MARK: - Karaoke State

    /// Words of the current utterance being highlighted.
    private var words: [String] = []

    /// Per-word timing intervals for karaoke advancement.
    private var wordTimings: [TimeInterval] = []

    /// Generation counter to invalidate stale work items on interruption.
    private var generation: Int = 0

    /// Pending work items for scheduled word highlights and linger-then-hide.
    private var scheduledWorkItems: [DispatchWorkItem] = []

    /// Work item for the post-utterance linger/hide delay (cancelled on new utterance).
    private var lingerWorkItem: DispatchWorkItem?

    // MARK: - Subviews

    /// Height constraint for the text field, updated in positionOnScreen() to
    /// ensure 2 lines of bold text fit. Without this, Auto Layout collapses the
    /// text field to its intrinsic single-line height.
    private var textFieldHeightConstraint: NSLayoutConstraint?

    /// Background container with rounded corners and translucent fill.
    private let backgroundView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// The label that displays subtitle text (plain or attributed).
    private let textField: NSTextField = {
        let field = NSTextField(wrappingLabelWithString: "")
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = SubtitleStyle.futureWordColor
        field.font = SubtitleStyle.regularFont
        field.alignment = .center
        field.maximumNumberOfLines = SubtitleStyle.maxLines
        field.cell?.truncatesLastVisibleLine = SubtitleStyle.truncatesLastVisibleLine
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
        logDiagnostics(label: "show(text:)", text: text)
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
        logDiagnostics(label: "updateAttributedText", text: text.string)
    }

    /// Build and display an NSAttributedString with karaoke-style word coloring.
    ///
    /// - Words before `index`: silver-grey, regular weight (already spoken)
    /// - Word at `index`: gold, bold weight (currently spoken)
    /// - Words after `index`: white, regular weight (upcoming)
    func highlightWord(at index: Int, in words: [String]) {
        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        // Space attributes must include the paragraph style — otherwise the
        // unstyled space characters get the default paragraph style (which uses
        // .byClipping), breaking word-wrap for the entire attributed string.
        let spaceAttributes: [NSAttributedString.Key: Any] = [
            .font: SubtitleStyle.regularFont,
            .paragraphStyle: paragraphStyle,
        ]

        for (i, word) in words.enumerated() {
            let color: NSColor
            let font: NSFont
            if i < index {
                color = SubtitleStyle.pastWordColor
                font = SubtitleStyle.regularFont
            } else if i == index {
                color = SubtitleStyle.currentWordColor
                font = SubtitleStyle.currentWordFont
            } else {
                color = SubtitleStyle.futureWordColor
                font = SubtitleStyle.regularFont
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: font,
                .paragraphStyle: paragraphStyle,
            ]
            if i > 0 {
                result.append(NSAttributedString(string: " ", attributes: spaceAttributes))
            }
            result.append(NSAttributedString(string: word, attributes: attributes))
        }

        updateAttributedText(result)
    }

    /// Display multiple pages of subtitle text with karaoke highlighting.
    /// Audio plays continuously as a single WAV; pages flip when karaoke
    /// reaches the last word of each page.
    func showPages(_ pages: [SubtitlePage], wordTimings: [TimeInterval]) {
        cancelScheduledHighlights()
        guard !pages.isEmpty else { return }

        generation += 1
        let myGeneration = generation

        var cumulativeTime: TimeInterval = 0

        for (_, page) in pages.enumerated() {
            let pageStartTime = cumulativeTime
            let pageWords = page.words

            // Schedule page display: show all words in future (white) color
            let showPageItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.generation == myGeneration else { return }
                self.highlightWord(at: -1, in: pageWords)
            }
            scheduledWorkItems.append(showPageItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + pageStartTime, execute: showPageItem)

            // Schedule per-word karaoke highlights within this page
            for localIndex in 0..<page.wordCount {
                let globalIndex = page.startWordIndex + localIndex
                let timing = globalIndex < wordTimings.count ? wordTimings[globalIndex] : 0.2
                let fireTime = cumulativeTime

                let capturedLocalIndex = localIndex
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self, self.generation == myGeneration else { return }
                    self.highlightWord(at: capturedLocalIndex, in: pageWords)
                }
                scheduledWorkItems.append(item)
                DispatchQueue.main.asyncAfter(deadline: .now() + fireTime, execute: item)
                cumulativeTime += timing
            }
        }

        // Linger on last page then hide
        let lingerItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == myGeneration else { return }
            self.hide()
        }
        self.lingerWorkItem = lingerItem
        scheduledWorkItems.append(lingerItem)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + cumulativeTime + SubtitleStyle.lingerDuration,
            execute: lingerItem
        )
    }

    /// Display an utterance with word-level karaoke highlighting driven by timing data.
    ///
    /// Wraps showPages() with a single page for backward compatibility.
    /// Used by demo() and simple text display.
    func showUtterance(_ text: String, wordTimings: [TimeInterval]) {
        let words = text.split(separator: " ").map(String.init)
        let singlePage = SubtitlePage(words: words, startWordIndex: 0)
        showPages([singlePage], wordTimings: wordTimings)
    }

    /// Run a demo sequence of three sample sentences with 200ms per-word timing.
    ///
    /// Sentences are scheduled sequentially: each starts after the previous one
    /// finishes highlighting + lingers + a short gap.
    func demo() {
        let sentences = [
            "Welcome to claude TTS companion, your real-time subtitle overlay",
            "This is a demo of the karaoke highlighting system",
            "Words light up in gold as they are spoken aloud",
        ]
        var delay: TimeInterval = 0.5  // initial delay
        for sentence in sentences {
            let words = sentence.split(separator: " ").map(String.init)
            let timings = Array(repeating: 0.2, count: words.count)  // 200ms per word
            let sentenceDelay = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + sentenceDelay) { [weak self] in
                self?.showUtterance(sentence, wordTimings: timings)
            }
            // Next sentence starts after this one finishes + linger + gap
            delay += Double(words.count) * 0.2 + SubtitleStyle.lingerDuration + 0.5
        }
    }

    // MARK: - Private Helpers

    /// Cancel all pending word-highlight and linger work items.
    private func cancelScheduledHighlights() {
        generation += 1
        for item in scheduledWorkItems {
            item.cancel()
        }
        scheduledWorkItems.removeAll()
        lingerWorkItem?.cancel()
        lingerWorkItem = nil
    }

    /// Configure all NSPanel window-behavior flags.
    private func configureWindowBehavior() {
        // SUB-01: Always on top
        level = .floating

        // SUB-11: Visible on all Spaces and over fullscreen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // SUB-08: Read-only sharing — visible to screencapture for diagnostics,
        // but content cannot be interacted with by screen sharing tools.
        sharingType = .readOnly

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

        // Text field inside background with padding.
        //
        // Uses a height constraint instead of bottom-pinning to prevent
        // Auto Layout from collapsing the text field to single-line intrinsic
        // height (which would shrink the entire window to 57px via the
        // background → content view → window constraint chain).
        backgroundView.addSubview(textField)
        let heightConstraint = textField.heightAnchor.constraint(equalToConstant: 0)
        textFieldHeightConstraint = heightConstraint
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
            heightConstraint,
        ])
    }

    /// Position the panel at bottom center of the main screen (SUB-02).
    func positionOnScreen() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelWidth = screenFrame.width * SubtitleStyle.widthRatio

        // Height sized for 2 lines of bold text (karaoke current word is bold)
        // plus inter-line spacing. Use ceil to avoid sub-pixel clipping.
        //
        // NOTE: `boundingRectForFont.height` is the tight glyph bounding box
        // (~14pt for 28pt font), NOT the typographic line height (~34pt).
        // The correct line height is ascender - descender + leading.
        let font = SubtitleStyle.currentWordFont
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let interLineSpacing: CGFloat = 4
        let panelHeight = lineHeight * CGFloat(SubtitleStyle.maxLines)
            + interLineSpacing
            + SubtitleStyle.verticalPadding * 2

        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screen.frame.origin.y + SubtitleStyle.bottomOffset

        let frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        // Update the text field height constraint to match 2 lines.
        // This drives Auto Layout to size the window correctly instead of
        // collapsing to the text field's intrinsic single-line height.
        let textFieldHeight = panelHeight - SubtitleStyle.verticalPadding * 2
        textFieldHeightConstraint?.constant = textFieldHeight

        setFrame(frame, display: true)

        // Tell the text field the width at which to wrap (required for multi-line layout)
        let textWidth = panelWidth - SubtitleStyle.horizontalPadding * 2
        textField.preferredMaxLayoutWidth = textWidth
    }

    // MARK: - Diagnostic Logging

    /// Log panel and text field dimensions for wrapping diagnostics.
    ///
    /// Since the panel has `sharingType = .none` (invisible to screenshots),
    /// log-based telemetry is the only way to verify multi-line rendering.
    private func logDiagnostics(label: String, text: String) {
        let panelFrame = frame
        let tfFrame = textField.frame
        let prefMaxWidth = textField.preferredMaxLayoutWidth
        let maxLines = textField.maximumNumberOfLines

        // Measure the text width using the bold font (worst-case width)
        let measuredWidth = SubtitleChunker.measureWidth(text)
        let availableWidth = tfFrame.width

        // Count rendered lines using NSLayoutManager for accurate line fragment enumeration
        let renderedLines: Int
        if !text.isEmpty {
            let attrStr: NSAttributedString
            if textField.attributedStringValue.length > 0 {
                attrStr = textField.attributedStringValue
            } else {
                attrStr = NSAttributedString(
                    string: text,
                    attributes: [.font: SubtitleStyle.regularFont]
                )
            }
            // Ensure the measurement uses word wrapping (matches the text field config)
            let measuredAttr = NSMutableAttributedString(attributedString: attrStr)
            if measuredAttr.length > 0 {
                let ps = NSMutableParagraphStyle()
                ps.lineBreakMode = .byWordWrapping
                measuredAttr.addAttribute(
                    .paragraphStyle, value: ps,
                    range: NSRange(location: 0, length: measuredAttr.length)
                )
            }
            let textStorage = NSTextStorage(attributedString: measuredAttr)
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(
                size: NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
            )
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)

            // Force layout then count line fragments
            layoutManager.ensureLayout(for: textContainer)
            var lineCount = 0
            var index = 0
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            while index < NSMaxRange(glyphRange) {
                var lineRange = NSRange()
                layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange)
                lineCount += 1
                index = NSMaxRange(lineRange)
            }
            renderedLines = lineCount
        } else {
            renderedLines = 0
        }

        logger.info("""
            [\(label)] panel=\(Int(panelFrame.width))x\(Int(panelFrame.height)) \
            tf=\(Int(tfFrame.width))x\(Int(tfFrame.height)) \
            prefMaxW=\(Int(prefMaxWidth)) maxLines=\(maxLines) \
            measuredW=\(Int(measuredWidth)) availW=\(Int(availableWidth)) \
            renderedLines=\(renderedLines) \
            wraps=\(measuredWidth > availableWidth) \
            text=\"\(text.prefix(80))\"
            """)
    }
}
