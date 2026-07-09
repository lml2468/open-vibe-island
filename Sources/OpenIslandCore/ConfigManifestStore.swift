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
    /// Decodes a manifest from `url`, or returns `nil` when the file is absent.
    /// Throws only when a present file fails to decode — never resets on absence.
    static func load<M: Decodable>(at url: URL, fileManager: FileManager) throws -> M? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(M.self, from: data)
    }

    /// Encodes `manifest` (iso8601 dates, pretty-printed + sorted keys) and writes
    /// it atomically to `url`.
    static func write<M: Encodable>(_ manifest: M, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    /// Resolves the hooks binary to record: the standardized `explicitURL` when
    /// given, otherwise the `managedBinaryURL` iff it is an executable file, else nil.
    static func resolvedBinaryURL(
        managedBinaryURL: URL,
        explicitURL: URL?,
        fileManager: FileManager
    ) -> URL? {
        if let explicitURL {
            return explicitURL.standardizedFileURL
        }

        guard fileManager.isExecutableFile(atPath: managedBinaryURL.path) else {
            return nil
        }

        return managedBinaryURL
    }
}
