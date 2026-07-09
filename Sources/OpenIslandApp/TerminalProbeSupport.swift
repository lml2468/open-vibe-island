import Foundation

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
