import Foundation

/// Epic #51-A3: splits a chat-message array into a visible part and an
/// archive part once the conversation exceeds `visibleLimit` messages.
/// Prevents UI bloat in long conversations (ChatView shows only the visible
/// tail; the user can expand the archive themselves if desired).
///
/// The current `ChatViewModel.fetchAIResponse` does not send message history
/// to Gemini — every turn is a one-shot call with only the context prefix.
/// Therefore trimming has no effect on the AI memory; it is purely a
/// UI/memory optimisation. Clear actions are not destructive: the archive
/// stays in the ChatViewModel and is one tap away.
///
/// Pure-Swift so the trim logic is testable independently of SwiftUI/SwiftData.
enum ChatConversationTrimmer {

    /// Threshold above which older messages move to the archive by default.
    /// 50 is chosen because the acceptance criteria explicitly mention "50 messages
    /// don't break the coach" — that keeps the whole recent conversation in view
    /// and archiving only kicks in for genuinely very long sessions.
    static let defaultVisibleLimit = 50

    /// Splits `messages` into two arrays: all messages that fold out of view
    /// (`archived`) and the messages that stay directly visible (`visible`).
    /// The order of the array is preserved — `archived` holds the oldest,
    /// `visible` the most recent `visibleLimit` messages.
    ///
    /// Generic over `Element` so the helper knows nothing about `ChatMessage` itself
    /// — that way it compiles in unit tests without the SwiftData/SwiftUI chain
    /// that `ChatMessage` brings along.
    static func split<Element>(messages: [Element],
                               visibleLimit: Int = defaultVisibleLimit) -> (archived: [Element], visible: [Element]) {
        guard visibleLimit > 0 else { return (messages, []) }
        guard messages.count > visibleLimit else { return ([], messages) }

        let archivedCount = messages.count - visibleLimit
        let archived = Array(messages.prefix(archivedCount))
        let visible = Array(messages.suffix(visibleLimit))
        return (archived, visible)
    }
}
