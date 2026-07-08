import Foundation

/// Shared persistence for the per-agent session registries.
///
/// `ClaudeSessionRegistry`, `CursorSessionRegistry`, `OpenCodeSessionRegistry`,
/// and `CodexSessionStore` all persist a `[Record]` to a JSON file with the exact
/// same policy (ISO-8601 dates, pretty-printed + sorted keys, atomic write,
/// directory auto-created, missing file → empty). That logic used to be
/// copy-pasted into each type; it now lives here once. The registry types remain
/// as thin, named wrappers that own only their default file URL and record type.
///
/// The on-disk format is intentionally unchanged, so files written by the old
/// per-type code still load and vice versa.
enum SessionRegistryStore {
    /// Load records from `fileURL`. A missing file is not an error — returns `[]`.
    static func load<Record: Decodable>(
        _ type: Record.Type = Record.self,
        from fileURL: URL,
        fileManager: FileManager
    ) throws -> [Record] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Record].self, from: data)
    }

    /// Atomically write `records` to `fileURL`, creating the directory if needed.
    static func save<Record: Encodable>(
        _ records: [Record],
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
