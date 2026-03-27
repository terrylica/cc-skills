import Foundation
import SwiftTelegramBot

/// Manages inline button state for Telegram notification keyboards.
///
/// Tracks notification lookups (shared by Follow Up and Transcript buttons)
/// and Focus Tab message deduplication (removes old keyboards when a new
/// notification arrives for the same iTerm tab).
///
/// Not Sendable -- accessed only from TelegramBot which is @unchecked Sendable.
final class InlineButtonManager {

    // MARK: - Types

    struct NotificationData {
        let cwd: String
        let workspace: String
        let transcriptPath: String
    }

    struct FocusTabEntry {
        let chatId: Int64
        let messageId: Int
    }

    /// Stored transcript page chunks for pagination (txp: callbacks).
    struct TranscriptPageStore {
        let chunks: [String]
        let createdAt: Date
    }

    // MARK: - State

    /// Auto-incrementing counter for notification IDs.
    private var notifCounter: Int = 0

    /// Maps notification counter to session data. Bounded to 200 entries (FIFO).
    private var notifLookup: [Int: NotificationData] = [:]

    /// Maps iTerm session UUID to the last message with Focus Tab button.
    /// Bounded to 100 entries (FIFO).
    private var focusTabMessages: [String: FocusTabEntry] = [:]

    /// Insertion-order tracking for FIFO eviction.
    private var notifInsertionOrder: [Int] = []
    private var focusTabInsertionOrder: [String] = []

    /// Transcript page store for pagination. Bounded to 50 entries (FIFO).
    private var transcriptPages: [Int: TranscriptPageStore] = [:]
    private var transcriptPagesInsertionOrder: [Int] = []

    // MARK: - Constants

    private let maxNotifEntries = 200
    private let maxFocusTabEntries = 100
    private let maxTranscriptPages = 50

    // MARK: - Notification Lookup

    /// Register a notification and return its counter ID for callback_data.
    func registerNotification(cwd: String, workspace: String, transcriptPath: String) -> Int {
        notifCounter += 1
        let id = notifCounter
        notifLookup[id] = NotificationData(cwd: cwd, workspace: workspace, transcriptPath: transcriptPath)
        notifInsertionOrder.append(id)

        // FIFO eviction
        while notifLookup.count > maxNotifEntries, let oldest = notifInsertionOrder.first {
            notifInsertionOrder.removeFirst()
            notifLookup.removeValue(forKey: oldest)
        }

        return id
    }

    /// Look up notification data by counter ID.
    func lookupNotification(id: Int) -> NotificationData? {
        return notifLookup[id]
    }

    // MARK: - Focus Tab Dedup

    /// Get the previous Focus Tab message entry for an iTerm session (for dedup).
    /// Call this BEFORE trackFocusTab to get the old message that needs keyboard removal.
    func previousFocusTabMessage(itermSessionId: String) -> FocusTabEntry? {
        return focusTabMessages[itermSessionId]
    }

    /// Track the latest Focus Tab message for an iTerm session.
    func trackFocusTab(itermSessionId: String, chatId: Int64, messageId: Int) {
        // Remove old entry from insertion order if re-tracking same session
        if focusTabMessages[itermSessionId] != nil {
            focusTabInsertionOrder.removeAll { $0 == itermSessionId }
        }

        focusTabMessages[itermSessionId] = FocusTabEntry(chatId: chatId, messageId: messageId)
        focusTabInsertionOrder.append(itermSessionId)

        // FIFO eviction
        while focusTabMessages.count > maxFocusTabEntries, let oldest = focusTabInsertionOrder.first {
            focusTabInsertionOrder.removeFirst()
            focusTabMessages.removeValue(forKey: oldest)
        }
    }

    // MARK: - Transcript Page Store

    /// Store transcript chunks for pagination and return the notification ID as key.
    func storeTranscriptPages(notifId: Int, chunks: [String]) {
        transcriptPages[notifId] = TranscriptPageStore(chunks: chunks, createdAt: Date())
        transcriptPagesInsertionOrder.append(notifId)

        // FIFO eviction
        while transcriptPages.count > maxTranscriptPages, let oldest = transcriptPagesInsertionOrder.first {
            transcriptPagesInsertionOrder.removeFirst()
            transcriptPages.removeValue(forKey: oldest)
        }
    }

    /// Look up stored transcript pages by notification ID.
    func lookupTranscriptPages(notifId: Int) -> [String]? {
        return transcriptPages[notifId]?.chunks
    }

    // MARK: - Keyboard Construction

    /// Build an inline keyboard for an Arc Summary notification message.
    ///
    /// Layout: single row with [Focus Tab] [Follow Up] [Transcript]
    /// Focus Tab is only included when itermSessionId is non-nil.
    func buildInlineKeyboard(itermSessionId: String?, notifId: Int) -> TGInlineKeyboardMarkup {
        var buttons: [TGInlineKeyboardButton] = []

        if let sessionId = itermSessionId, !sessionId.isEmpty {
            buttons.append(TGInlineKeyboardButton(
                text: "\u{1F4FA} Focus Tab",
                callbackData: "iterm:\(sessionId)"
            ))
        }

        buttons.append(TGInlineKeyboardButton(
            text: "\u{1F4AC} Follow Up",
            callbackData: "fu:\(notifId)"
        ))

        buttons.append(TGInlineKeyboardButton(
            text: "\u{1F4CB} Transcript",
            callbackData: "tx:\(notifId)"
        ))

        return TGInlineKeyboardMarkup(inlineKeyboard: [buttons])
    }

    /// Build a pagination keyboard for transcript viewing.
    func buildTranscriptPaginationKeyboard(notifId: Int, currentPage: Int, totalPages: Int) -> TGInlineKeyboardMarkup {
        var buttons: [TGInlineKeyboardButton] = []

        if currentPage > 0 {
            buttons.append(TGInlineKeyboardButton(
                text: "\u{25C0}\u{FE0F} Prev",
                callbackData: "txp:\(notifId):\(currentPage - 1)"
            ))
        }

        buttons.append(TGInlineKeyboardButton(
            text: "\(currentPage + 1)/\(totalPages)",
            callbackData: "txp:\(notifId):\(currentPage)"
        ))

        if currentPage < totalPages - 1 {
            buttons.append(TGInlineKeyboardButton(
                text: "Next \u{25B6}\u{FE0F}",
                callbackData: "txp:\(notifId):\(currentPage + 1)"
            ))
        }

        return TGInlineKeyboardMarkup(inlineKeyboard: [buttons])
    }
}
