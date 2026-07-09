import Foundation

/// Shared escaping for values embedded inside an AppleScript double-quoted
/// string. Extracted from two identical private copies in `TerminalJumpService`
/// and `TerminalTextSender`.
enum AppleScriptEscaping {
    /// Escape a value for embedding inside an AppleScript double-quoted string:
    /// nil → empty; backslash first (so an already-escaped quote isn't
    /// double-processed), then double quote.
    static func escape(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
