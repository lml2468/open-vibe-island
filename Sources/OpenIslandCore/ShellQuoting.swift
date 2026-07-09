import Foundation

/// Shared POSIX single-quote shell escaping for hook-command strings written
/// into third-party agent config. Extracted from five byte-identical private
/// copies across the `*HookInstaller` types.
enum ShellQuoting {
    /// STUB (Red): real escaping filled in during Green.
    static func quote(_ string: String) -> String {
        string
    }
}
