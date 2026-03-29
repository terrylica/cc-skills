import AppKit
import Logging

/// A floating, interactive panel that displays scrollable caption history with timestamps.
///
/// Shows past subtitle captions in a two-column table (HH:MM timestamp + caption text).
/// Clicking a row copies that caption's text to the macOS clipboard.
/// Auto-scrolls to the latest entry unless the user has manually scrolled up.
@MainActor
public final class CaptionHistoryPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {

    private let logger = Logger(label: "caption-history-panel")

    // MARK: - Data

    /// Reference to the shared caption ring buffer.
    private let captionHistory: CaptionHistory

    /// Snapshot of entries currently displayed in the table.
    private var entries: [CaptionEntry] = []

    /// Tracks whether the user has manually scrolled away from the bottom.
    /// When true, auto-scroll on refresh is suppressed until the user returns to the bottom.
    private var isUserScrolling: Bool = false

    // MARK: - Subviews

    private let scrollView: NSScrollView
    private let tableView: NSTableView

    // MARK: - Formatters

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Column IDs

    private static let timeColumnID = NSUserInterfaceItemIdentifier("TimeColumn")
    private static let captionColumnID = NSUserInterfaceItemIdentifier("CaptionColumn")

    // MARK: - Initialization

    init(captionHistory: CaptionHistory) {
        self.captionHistory = captionHistory

        // Build table view
        let tv = NSTableView()
        tv.headerView = nil  // No header row -- columns are self-explanatory
        tv.usesAutomaticRowHeights = true  // Auto-size rows for word-wrapped text
        tv.intercellSpacing = NSSize(width: 8, height: 4)
        tv.usesAlternatingRowBackgroundColors = false
        tv.selectionHighlightStyle = .regular
        tv.style = .plain
        tv.gridStyleMask = []

        let timeCol = NSTableColumn(identifier: CaptionHistoryPanel.timeColumnID)
        timeCol.title = "Time"
        timeCol.width = 60
        timeCol.minWidth = 50
        timeCol.maxWidth = 80
        tv.addTableColumn(timeCol)

        let captionCol = NSTableColumn(identifier: CaptionHistoryPanel.captionColumnID)
        captionCol.title = "Caption"
        captionCol.minWidth = 150
        tv.addTableColumn(captionCol)

        self.tableView = tv

        // Build scroll view
        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView = sv

        // Window setup -- interactive (titled, closable, resizable) unlike SubtitlePanel
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 500
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screenFrame.origin.y + (screenFrame.height - panelHeight) / 2
        let contentRect = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Window behavior
        title = "Caption History"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .readOnly
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 300, height: 200)
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = NSColor(white: 0.1, alpha: 0.95)

        // Set up content view
        guard let content = contentView else { return }
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Dark scroll view background
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.1, alpha: 0.95)
        tv.backgroundColor = NSColor(white: 0.1, alpha: 0.95)

        // Wire data source and delegate
        tv.dataSource = self
        tv.delegate = self

        // Observe scroll to detect manual user scrolling (CAPT-02)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
    }

    // MARK: - Public API

    /// Show the panel, refreshing data from caption history and scrolling to bottom.
    func show() {
        reloadEntries()
        scrollToBottom()
        orderFrontRegardless()
        logger.info("Caption history panel shown with \(entries.count) entries")
    }

    /// Hide the panel.
    func hide() {
        orderOut(nil)
    }

    /// Refresh entries from caption history. Auto-scrolls to bottom unless user has scrolled up.
    func refresh() {
        reloadEntries()
        if !isUserScrolling {
            scrollToBottom()
        }
    }

    // MARK: - NSTableViewDataSource

    public nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        return MainActor.assumeIsolated { entries.count }
    }

    // MARK: - NSTableViewDelegate

    public nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        return MainActor.assumeIsolated {
            guard row < entries.count else { return nil }
            let entry = entries[row]

            let cellID = NSUserInterfaceItemIdentifier("Cell")
            let cell: NSTextField
            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
                cell = reused
            } else {
                cell = NSTextField(wrappingLabelWithString: "")
                cell.identifier = cellID
                cell.isEditable = false
                cell.isSelectable = true
                cell.isBezeled = false
                cell.drawsBackground = false
            }
            // Set wrapping properties every time (not just on creation) to ensure
            // reused cells don't retain stale settings from a different column.
            cell.maximumNumberOfLines = 0
            cell.cell?.truncatesLastVisibleLine = false
            cell.lineBreakMode = .byWordWrapping
            cell.cell?.wraps = true
            cell.preferredMaxLayoutWidth = tableView.tableColumns.last?.width ?? 300

            if tableColumn?.identifier == CaptionHistoryPanel.timeColumnID {
                cell.stringValue = formatTime(entry.timestamp)
                cell.textColor = NSColor.secondaryLabelColor
                cell.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                cell.alignment = .right
                cell.maximumNumberOfLines = 1
                cell.lineBreakMode = .byClipping
            } else {
                cell.stringValue = entry.text
                cell.textColor = NSColor.labelColor
                cell.font = NSFont.systemFont(ofSize: 13)
                cell.alignment = .left
                // Tooltip: UUID + sync telemetry for debugging
                var tip = "UUID: \(entry.uuid)"
                if let wc = entry.wordCount { tip += "\nWords: \(wc)" }
                if let oc = entry.onsetCount { tip += " | Onsets: \(oc)" }
                if let dur = entry.audioDuration { tip += " | Duration: \(String(format: "%.1f", dur))s" }
                if let wc = entry.wordCount, let oc = entry.onsetCount, wc != oc {
                    tip += "\n⚠️ MISMATCH: words≠onsets (sync may drift)"
                }
                cell.toolTip = tip
            }

            return cell
        }
    }

    /// Click-to-copy (CAPT-03): Clicking a row copies its caption text to the clipboard.
    public nonisolated func tableViewSelectionDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            let row = tableView.selectedRow
            guard row >= 0, row < entries.count else { return }
            let entry = entries[row]

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(entry.text, forType: .string)

            logger.info("Copied caption #\(entry.index) to clipboard: \(entry.text.prefix(50))")

            // Deselect after a brief delay for visual feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.tableView.deselectAll(nil)
            }
        }
    }

    // MARK: - Scroll Detection (CAPT-02)

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard let clipView = scrollView.contentView as? NSClipView,
              let documentView = scrollView.documentView else { return }

        let contentHeight = documentView.frame.height
        let scrollOffset = clipView.bounds.origin.y
        let visibleHeight = clipView.bounds.height
        let tolerance: CGFloat = 20

        // User is at bottom if scroll offset + visible height >= content height (within tolerance)
        let atBottom = scrollOffset + visibleHeight >= contentHeight - tolerance
        isUserScrolling = !atBottom
    }

    // MARK: - Private Helpers

    /// Reload entries from the caption history ring buffer and refresh the table.
    private func reloadEntries() {
        entries = captionHistory.getAll()
        tableView.reloadData()
    }

    /// Scroll the table view to the last row.
    private func scrollToBottom() {
        guard !entries.isEmpty else { return }
        tableView.scrollRowToVisible(entries.count - 1)
    }

    /// Format an ISO 8601 timestamp string to HH:mm display format.
    private func formatTime(_ isoString: String) -> String {
        guard let date = isoFormatter.date(from: isoString) else { return "--:--" }
        return timeFormatter.string(from: date)
    }
}
