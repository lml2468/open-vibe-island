import Foundation

/// A Ghostty terminal surface discovered via AppleScript. Shared by the terminal
/// probe/resolver pair (moved verbatim from their byte-identical nested copies).
struct GhosttyTerminalSnapshot: Sendable {
    var sessionID: String
    var workingDirectory: String
    var title: String
}

/// A Terminal.app tab discovered via AppleScript. Shared by the terminal
/// probe/resolver pair (moved verbatim from their byte-identical nested copies).
struct TerminalTabSnapshot: Sendable {
    var tty: String
    var customTitle: String
}

/// Shared helpers for the terminal AppleScript probe/resolver pair
/// (`TerminalJumpTargetResolver` and `TerminalSessionAttachmentProbe`), extracted
/// from their byte-identical private copies. Grows as later cluster-A slices land.
enum TerminalProbeSupport {
    /// Normalize a terminal app name for comparison: trim surrounding whitespace
    /// and lowercase.
    static func normalizedTerminalName(for value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
