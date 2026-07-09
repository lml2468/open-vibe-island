import Foundation

/// Shared escaping for values embedded inside an AppleScript double-quoted
/// string. Extracted from two identical private copies in `TerminalJumpService`
/// and `TerminalTextSender`.
enum AppleScriptEscaping {
    /// STUB (Red): real escaping filled in during Green.
    static func escape(_ value: String?) -> String {
        value ?? ""
    }
}
