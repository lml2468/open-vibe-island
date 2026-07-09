import Foundation

/// Shared manifest persistence + hooks-binary resolution for the hook
/// installation managers (Claude/Codex/Cursor/Gemini/Kimi), extracted from their
/// byte-identical `loadManifest` / inlined manifest-write / `resolvedHooksBinaryURL`
/// copies (slice `config-manifest-store`, discovery finding #9 cluster B).
///
/// Only the mechanical persistence lives here; each manager keeps its own
/// install/uninstall/status orchestration (and Claude/Codex their legacy
/// `resolvedManifestURL`). This preserves the blast-radius isolation
/// `installer-config-safety` calls for while removing the duplicated I/O.
enum ConfigManifestStore {
    // RED STUB — wrong values so the failing-first tests compile and fail on
    // assertion. Replaced in Green.
    static func load<M: Decodable>(at url: URL, fileManager: FileManager) throws -> M? {
        nil
    }

    static func write<M: Encodable>(_ manifest: M, to url: URL) throws {
        // no-op stub
    }

    static func resolvedBinaryURL(
        managedBinaryURL: URL,
        explicitURL: URL?,
        fileManager: FileManager
    ) -> URL? {
        nil
    }
}
