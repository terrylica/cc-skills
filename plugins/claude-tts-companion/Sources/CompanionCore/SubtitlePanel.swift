import AppKit
import Logging

/// A floating, click-through, screen-sharing-invisible subtitle overlay panel.
///
/// Positioned at the bottom center of the main display, this panel shows
/// up to 2 lines of word-wrapped text with karaoke-style highlighting.
/// All UI operations must occur on the main thread.
@MainActor
public final class SubtitlePanel: NSPanel {

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
        field.alignment = .left
        field.maximumNumberOfLines = SubtitleStyle.maxLines
        field.cell?.truncatesLastVisibleLine = SubtitleStyle.truncatesLastVisibleLine
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    // MARK: - Settings

    /// Settings store for dynamic font size and position (read on each display).
    private var settingsStore: SettingsStore?

    // MARK: - Initialization

    init(settingsStore: SettingsStore? = nil) {
        self.settingsStore = settingsStore
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

    /// Inject the settings store after initialization (for backward compatibility).
    func setSettingsStore(_ store: SettingsStore) {
        self.settingsStore = store
    }

    /// Read the current font size setting name from the settings store.
    /// Public so that callers (e.g., TelegramBot) can pass it to SubtitleChunker
    /// for consistent font-width measurement.
    var currentFontSizeName: String {
        settingsStore?.getSettings().subtitle.fontSize ?? "medium"
    }

    /// Read the current position setting from the settings store.
    private var currentPosition: String {
        settingsStore?.getSettings().subtitle.position ?? "bottom"
    }

    /// Read the current subtitle scope ("paragraph" or "sentence") from settings.
    var currentSubtitleScope: String {
        settingsStore?.getSettings().subtitle.subtitleScope ?? "paragraph"
    }

    /// Read the current display mode from the settings store.
    private var currentDisplayMode: DisplayMode {
        DisplayMode.from(string: settingsStore?.getSettings().subtitle.displayMode ?? "karaoke")
    }

    // MARK: - Focus Prevention (SUB-09)

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    // MARK: - Public API

    /// Show plain text in the subtitle panel (white, regular weight).
    /// When displayMode is `.bionic`, renders with bold-prefix formatting instead.
    func show(text: String) {
        if currentDisplayMode == .bionic {
            let words = text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
            let attributed = BionicRenderer.render(words: words, fontSizeName: currentFontSizeName)
            textField.attributedStringValue = attributed
        } else {
            let font = SubtitleStyle.dynamicRegularFont(currentFontSizeName)
            textField.font = font
            textField.stringValue = text
        }
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
    ///
    /// - Parameter isPageTransition: When `true`, runs the full display pipeline
    ///   (positionOnScreen, orderFrontRegardless, logDiagnostics). When `false`
    ///   (default, 60Hz hot path), only sets `textField.attributedStringValue` to
    ///   minimize main-thread work and avoid starving AVAudioPlayer's run loop.
    func highlightWord(at index: Int, in words: [String], isPageTransition: Bool = false, paragraphBreaksAfter: Set<Int> = []) {
        let sizeName = currentFontSizeName
        let mode = currentDisplayMode

        // Bionic mode: bold-prefix rendering, no karaoke gold/grey coloring (BION-04)
        if mode == .bionic {
            let attributed = BionicRenderer.render(words: words, fontSizeName: sizeName)
            if isPageTransition {
                updateAttributedText(attributed)
            } else {
                textField.attributedStringValue = attributed
            }
            return
        }

        // Plain mode: all white, regular weight, no highlighting
        if mode == .plain {
            let regFont = SubtitleStyle.dynamicRegularFont(sizeName)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            paragraphStyle.lineBreakMode = .byWordWrapping
            let result = NSMutableAttributedString()
            for (i, word) in words.enumerated() {
                if i > 0 {
                    result.append(NSAttributedString(string: " ", attributes: [
                        .font: regFont, .foregroundColor: SubtitleStyle.futureWordColor,
                        .paragraphStyle: paragraphStyle,
                    ]))
                }
                result.append(NSAttributedString(string: word, attributes: [
                    .font: regFont, .foregroundColor: SubtitleStyle.futureWordColor,
                    .paragraphStyle: paragraphStyle,
                ]))
            }
            if isPageTransition {
                updateAttributedText(result)
            } else {
                textField.attributedStringValue = result
            }
            return
        }

        // Karaoke mode (default): gold/grey/white word coloring
        let boldFont = SubtitleStyle.dynamicCurrentWordFont(sizeName)
        let regFont = SubtitleStyle.dynamicRegularFont(sizeName)

        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        // Space attributes must include the paragraph style — otherwise the
        // unstyled space characters get the default paragraph style (which uses
        // .byClipping), breaking word-wrap for the entire attributed string.
        let spaceAttributes: [NSAttributedString.Key: Any] = [
            .font: regFont,
            .paragraphStyle: paragraphStyle,
        ]

        for (i, word) in words.enumerated() {
            let color: NSColor
            let font: NSFont
            if i < index {
                color = SubtitleStyle.pastWordColor
                font = regFont
            } else if i == index {
                color = SubtitleStyle.currentWordColor
                font = boldFont
            } else {
                color = SubtitleStyle.futureWordColor
                font = regFont
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
            // Insert paragraph break after this word if marked
            if paragraphBreaksAfter.contains(i) {
                result.append(NSAttributedString(string: "\n", attributes: spaceAttributes))
            }
        }

        if isPageTransition {
            updateAttributedText(result)
        } else {
            // Lightweight path: only update the text content, skip expensive
            // positionOnScreen(), orderFrontRegardless(), and logDiagnostics().
            // Position is already set from the page transition call.
            textField.attributedStringValue = result
        }
    }

    /// Display multiple pages of subtitle text with karaoke highlighting.
    /// Audio plays continuously as a single WAV; pages flip when karaoke
    /// reaches the last word of each page.
    func showPages(_ pages: [SubtitlePage], wordTimings: [TimeInterval]) {
        cancelScheduledHighlights()
        guard !pages.isEmpty else { return }

        generation += 1
        let myGeneration = generation

        // Diagnostic: log page structure
        logger.info("[showPages] gen=\(myGeneration) totalPages=\(pages.count) totalWordTimings=\(wordTimings.count)")
        for (pi, page) in pages.enumerated() {
            let preview = page.words.prefix(5).joined(separator: " ")
            let lastWords = page.words.suffix(3).joined(separator: " ")
            logger.info("[showPages] page[\(pi)] startIdx=\(page.startWordIndex) wordCount=\(page.wordCount) first=\"\(preview)\" last=\"\(lastWords)\"")
        }

        // No launch delay needed -- CADisplayLink polls AVAudioPlayer.currentTime
        // for production audio. This timer path is only used by demo().
        let scheduleStart = DispatchTime.now()
        var cumulativeTime: TimeInterval = 0

        for (pageIndex, page) in pages.enumerated() {
            let pageStartTime = cumulativeTime
            let pageWords = page.words
            let capturedPageIndex = pageIndex

            // Schedule page display: show all words in future (white) color
            let showPageItem = DispatchWorkItem { [weak self] in
                guard let self = self else {
                    Logger(label: "subtitle-panel").info("[showPages] page[\(capturedPageIndex)] showPageItem: self=nil, skipping")
                    return
                }
                let genMatch = self.generation == myGeneration
                self.logger.info("[showPages] page[\(capturedPageIndex)] showPageItem FIRED gen=\(myGeneration) current=\(self.generation) match=\(genMatch)")
                guard genMatch else { return }
                self.highlightWord(at: -1, in: pageWords, isPageTransition: true)
            }
            scheduledWorkItems.append(showPageItem)
            DispatchQueue.main.asyncAfter(deadline: scheduleStart + pageStartTime, execute: showPageItem)
            logger.info("[showPages] page[\(capturedPageIndex)] showPageItem scheduled at +\(String(format: "%.3f", pageStartTime))s")

            // Schedule per-word karaoke highlights within this page
            for localIndex in 0..<page.wordCount {
                let globalIndex = page.startWordIndex + localIndex
                let timing = globalIndex < wordTimings.count ? wordTimings[globalIndex] : 0.2
                let fireTime = cumulativeTime

                let capturedLocalIndex = localIndex
                let capturedFireTime = fireTime
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    let genMatch = self.generation == myGeneration
                    if capturedLocalIndex == 0 || capturedLocalIndex == pageWords.count - 1 {
                        self.logger.info("[showPages] page[\(capturedPageIndex)] word[\(capturedLocalIndex)/\(pageWords.count)] FIRED at +\(String(format: "%.3f", capturedFireTime))s gen=\(myGeneration) current=\(self.generation) match=\(genMatch) word=\"\(pageWords[capturedLocalIndex])\"")
                    }
                    guard genMatch else { return }
                    self.highlightWord(at: capturedLocalIndex, in: pageWords)
                }
                scheduledWorkItems.append(item)
                DispatchQueue.main.asyncAfter(deadline: scheduleStart + fireTime, execute: item)
                cumulativeTime += timing
            }

            logger.info("[showPages] page[\(capturedPageIndex)] words scheduled: cumulativeTime=\(String(format: "%.3f", cumulativeTime))s")
        }

        // Linger on last page then hide
        let lingerFireTime = cumulativeTime + SubtitleStyle.lingerDuration
        let lingerItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let genMatch = self.generation == myGeneration
            self.logger.info("[showPages] lingerHide FIRED gen=\(myGeneration) current=\(self.generation) match=\(genMatch)")
            guard genMatch else { return }
            self.hide()
        }
        self.lingerWorkItem = lingerItem
        scheduledWorkItems.append(lingerItem)
        DispatchQueue.main.asyncAfter(
            deadline: scheduleStart + lingerFireTime,
            execute: lingerItem
        )

        logger.info("[showPages] scheduling complete: \(scheduledWorkItems.count) items, totalDuration=\(String(format: "%.3f", cumulativeTime))s, lingerAt=\(String(format: "%.3f", lingerFireTime))s")
    }

    /// Display an utterance with word-level karaoke highlighting driven by timing data.
    ///
    /// Wraps showPages() with a single page for backward compatibility.
    /// Used by demo() and simple text display.
    func showUtterance(_ text: String, wordTimings: [TimeInterval]) {
        let words = text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
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

        // Draggable — user can reposition by clicking and dragging anywhere on the panel.
        // Last drag position is persisted and restored on next show.
        ignoresMouseEvents = false
        isMovableByWindowBackground = true

        // Transparent chrome
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    /// Save position after user drags the panel.
    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        UserDefaults.standard.set(frame.origin.x, forKey: "subtitlePanelX")
        UserDefaults.standard.set(frame.origin.y, forKey: "subtitlePanelY")
        UserDefaults.standard.set(true, forKey: "subtitlePanelPositionSaved")
    }

    /// Build the view hierarchy: background view + centered text field.
    private func configureContentView() {
        guard let content = contentView else { return }

        // Background with rounded corners, solid fill, and white border
        content.addSubview(backgroundView)
        backgroundView.layer?.backgroundColor = SubtitleStyle.backgroundColor.cgColor
        backgroundView.layer?.cornerRadius = SubtitleStyle.cornerRadius
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.borderColor = NSColor.white.cgColor
        backgroundView.layer?.borderWidth = 2.0

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

    /// Position the panel on the main screen based on current settings (SUB-02).
    ///
    /// Reads font size and position from SettingsStore on every call, so
    /// changes made via the HTTP API take effect on the next subtitle display.
    func positionOnScreen() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelWidth = screenFrame.width * SubtitleStyle.widthRatio

        // Use the dynamic font size from settings (small/medium/large)
        let font = SubtitleStyle.dynamicCurrentWordFont(currentFontSizeName)

        // Auto-size height: use NSTextFieldCell.cellSize(forBounds:) for accurate
        // measurement with attributed strings (mixed fonts, word wrap).
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let textWidth = panelWidth - SubtitleStyle.horizontalPadding * 2
        textField.preferredMaxLayoutWidth = textWidth

        let measuredHeight: CGFloat
        if let cell = textField.cell, textField.attributedStringValue.length > 0 {
            let cellSize = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: CGFloat.greatestFiniteMagnitude))
            measuredHeight = max(lineHeight * 2, ceil(cellSize.height))
        } else {
            measuredHeight = lineHeight * 2
        }
        // Cap at 60% of screen height
        let maxHeight = screenFrame.height * 0.6
        let panelHeight = min(measuredHeight + SubtitleStyle.verticalPadding * 2, maxHeight)

        // Restore last user-dragged position if available, otherwise use configured position.
        let savedX = UserDefaults.standard.double(forKey: "subtitlePanelX")
        let savedY = UserDefaults.standard.double(forKey: "subtitlePanelY")
        let hasSavedPosition = UserDefaults.standard.bool(forKey: "subtitlePanelPositionSaved")

        let x: CGFloat
        let y: CGFloat
        if hasSavedPosition {
            x = savedX
            y = savedY
        } else {
            x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
            if currentPosition == "top" {
                y = screenFrame.origin.y + screenFrame.height - panelHeight - SubtitleStyle.topOffset
            } else if currentPosition == "middle" {
                y = screenFrame.origin.y + (screenFrame.height - panelHeight) / 2
            } else {
                y = screen.frame.origin.y + SubtitleStyle.bottomOffset
            }
        }

        let frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        // Update the text field height constraint to match 2 lines.
        // This drives Auto Layout to size the window correctly instead of
        // collapsing to the text field's intrinsic single-line height.
        let textFieldHeight = panelHeight - SubtitleStyle.verticalPadding * 2
        textFieldHeightConstraint?.constant = textFieldHeight

        setFrame(frame, display: true)

        // Tell the text field the width at which to wrap (required for multi-line layout)
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
        let measuredWidth = SubtitleChunker.measureWidth(text, fontSizeName: currentFontSizeName)
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
