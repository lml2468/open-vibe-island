import Foundation

/// Shared pretty-printed, key-sorted JSON serialization for the hook installers.
/// Extracted from four byte-identical private `serialize(_:)` copies across the
/// JSON-config `*HookInstaller` types (Claude/Codex/Cursor/Gemini). `.sortedKeys`
/// keeps writes deterministic; matching the original options preserves on-disk
/// output byte-for-byte (see the installer-config-safety rule).
enum JSONConfigSerialization {
    /// STUB (Red): real serialization filled in during Green.
    static func serialize(_ object: [String: Any]) throws -> Data {
        Data()
    }
}
