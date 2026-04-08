import AppKit
import Logging

/// Floating subtitle overlay with karaoke word highlighting. @MainActor.
@MainActor
public final class SubtitlePanel: NSPanel {

    let logger = Logger(label: "subtitle-panel")

    // MARK: - Karaoke State

    private var words: [String] = []
    private var wordTimings: [TimeInterval] = []
    private var generation: Int = 0
    private var scheduledWorkItems: [DispatchWorkItem] = []
    private var lingerWorkItem: DispatchWorkItem?
    private var textFieldHeightConstraint: NSLayoutConstraint?

    /// Clipboard + UUID display handler.
    let clipboard = SubtitleClipboard()

    /// Background container with rounded corners and solid fill.
    private let backgroundView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Animated rainbow gradient border.
    private let border = SubtitleBorder()

    /// The label that displays subtitle text (plain or attributed).
    let textField: NSTextField = {
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
        pendingLingerHide?.cancel()
        pendingLingerHide = nil
        positionOnScreen()
        orderFrontRegardless()
        logDiagnostics(label: "show(text:)", text: text)
    }

    /// Hide the subtitle panel.
    func hide() {
        pendingLingerHide?.cancel()
        pendingLingerHide = nil
        clearEdgeHint()
        orderOut(nil)
    }

    /// Pending linger-hide work item. Cancelled whenever new content is shown
    /// (via orderFrontRegardless) so stale timers from old playback sessions
    /// never hide subtitles that a new driver is actively displaying.
    private var pendingLingerHide: DispatchWorkItem?

    /// Schedule a hide after the linger duration. Automatically cancelled if
    /// new content is shown before the timer fires (orderFrontRegardless
    /// cancels pendingLingerHide).
    func lingerThenHide() {
        lingerThenHide(after: SubtitleStyle.lingerDuration)
    }

    /// Schedule a hide after a custom delay. Uses the same pendingLingerHide
    /// mechanism as lingerThenHide() -- automatically cancelled if new content
    /// is shown (show/updateAttributedText cancel pendingLingerHide).
    func lingerThenHide(after delay: TimeInterval) {
        pendingLingerHide?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.pendingLingerHide = nil
            self?.clearEdgeHint()
            self?.orderOut(nil)
        }
        pendingLingerHide = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Show attributed text for karaoke highlighting (gold/grey/white per word).
    func updateAttributedText(_ text: NSAttributedString) {
        pendingLingerHide?.cancel()
        pendingLingerHide = nil
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

        // Bionic mode: bold-prefix rendering with gold highlight on current word
        if mode == .bionic {
            let bionicOpacity = CGFloat(settingsStore?.getSettings().subtitle.bionicSuffixOpacity ?? 0.7)
            let attributed = BionicRenderer.render(
                words: words,
                fontSizeName: sizeName,
                highlightIndex: index,
                paragraphBreaksAfter: paragraphBreaksAfter,
                suffixOpacity: bionicOpacity
            )
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
        SubtitlePosition.save(frame: frame)
    }

    /// Build the view hierarchy: background view + centered text field.
    private func configureContentView() {
        guard let content = contentView else { return }

        // Background with rounded corners, solid fill, and animated rainbow border
        content.addSubview(backgroundView)
        backgroundView.layer?.backgroundColor = SubtitleStyle.backgroundColor.cgColor
        backgroundView.layer?.cornerRadius = SubtitleStyle.cornerRadius
        backgroundView.layer?.masksToBounds = false

        // Attach animated rainbow gradient border
        if let layer = backgroundView.layer {
            border.attach(to: layer, cornerRadius: SubtitleStyle.cornerRadius)
        }

        // Pin background to fill the content view
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: content.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Text field with height constraint (prevents Auto Layout single-line collapse)
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

        // UUID label (bottom-right, subtle gray)
        clipboard.attach(to: backgroundView,
            trailingAnchor: backgroundView.trailingAnchor,
            bottomAnchor: backgroundView.bottomAnchor)
    }

    /// Right-click (two-finger tap) copies subtitle + UUID to clipboard.
    public override func rightMouseDown(with event: NSEvent) {
        clipboard.copyToClipboard()
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

        let textWidth = panelWidth - SubtitleStyle.horizontalPadding * 2
        textField.preferredMaxLayoutWidth = textWidth

        let panelHeight = SubtitlePosition.measureHeight(
            textField: textField, font: font, textWidth: textWidth, screenHeight: screenFrame.height
        )

        let frame = SubtitlePosition.calculateFrame(
            panelWidth: panelWidth, panelHeight: panelHeight,
            screenFrame: screenFrame, screenFullFrame: screen.frame,
            preset: currentPosition
        )

        // Update the text field height constraint to match 2 lines.
        // This drives Auto Layout to size the window correctly instead of
        // collapsing to the text field's intrinsic single-line height.
        let textFieldHeight = panelHeight - SubtitleStyle.verticalPadding * 2
        textFieldHeightConstraint?.constant = textFieldHeight

        setFrame(frame, display: true)

        // Tell the text field the width at which to wrap (required for multi-line layout)
        textField.preferredMaxLayoutWidth = textWidth

        // Update rainbow border to match new panel bounds
        border.updateFrame(bounds: backgroundView.bounds, cornerRadius: SubtitleStyle.cornerRadius)
    }

    // MARK: - Border Edge Hints

    /// Update the jagged waveform edges on the rainbow border to indicate bisected paragraph state.
    func setEdgeHint(_ hint: SubtitleBorder.EdgeHint) {
        border.setEdgeHint(hint, bounds: backgroundView.bounds)
    }

    /// Clear any jagged edges (restore normal rounded border).
    func clearEdgeHint() {
        border.clearEdgeHint(bounds: backgroundView.bounds)
    }

}
