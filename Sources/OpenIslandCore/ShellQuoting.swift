import Foundation

/// Shared POSIX single-quote shell escaping for hook-command strings written
/// into third-party agent config. Extracted from five byte-identical private
/// copies across the `*HookInstaller` types.
enum ShellQuoting {
    /// POSIX single-quote escape: empty → `''`; otherwise wrap in single quotes,
    /// escaping any embedded single quote via the `'\''` idiom (close-quote,
    /// escaped literal quote, reopen-quote).
    static func quote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
