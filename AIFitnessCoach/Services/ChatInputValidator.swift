import Foundation

/// Epic #51-A4: guards the chat input against paste actions that push the Gemini
/// prompt into 45s timeouts or safety blocks. The pre-#51 implementation
/// had no limit and no visual feedback — a user who pasted a PDF quote
/// into the input only got a vague error back after three minutes.
///
/// Pure-Swift so the clamp and counter logic is testable independently of SwiftUI.
enum ChatInputValidator {

    /// Maximum number of characters the coach accepts in one turn. 5000 chars
    /// roughly corresponds to ~1200 tokens — ample for an extensive
    /// reflection, well under the Gemini input window, and still leaves the prompt
    /// head-and-tail room for our context prefix.
    static let maxLength = 5000

    /// Threshold above which we show the char counter below the input field. 80%
    /// of the maximum: the counter only appears once the user enters the
    /// danger zone; during normal typing the UI stays calm.
    static let counterThreshold = 4000

    /// Clamp result that gives the caller information about what happened —
    /// `didClamp == true` means the input was truncated and a short toast
    /// is warranted.
    struct ClampResult: Equatable {
        let clamped: String
        let didClamp: Bool
    }

    /// Truncates `text` to `limit` characters. Returns `didClamp = true` once
    /// something was actually cut off, so the UI can show a one-time toast.
    static func clamp(_ text: String, limit: Int = maxLength) -> ClampResult {
        guard limit >= 0 else { return ClampResult(clamped: "", didClamp: !text.isEmpty) }
        if text.count <= limit {
            return ClampResult(clamped: text, didClamp: false)
        }
        let clamped = String(text.prefix(limit))
        return ClampResult(clamped: clamped, didClamp: true)
    }

    /// Determines whether the visual counter should be visible. The caller (ChatView)
    /// renders it below the TextField when this function returns `true`.
    static func shouldShowCounter(_ text: String, threshold: Int = counterThreshold) -> Bool {
        text.count >= threshold
    }
}
