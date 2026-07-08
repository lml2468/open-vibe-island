import Foundation
import Testing
@testable import OpenIslandCore

/// Covers the dedup-registries slice (arch-quality-audit #6, registry dimension):
/// the shared `SessionRegistryStore` persistence, `CodexSessionStore` round-trip
/// (previously untested), and on-disk format compatibility with files written by
/// the old per-type code.
struct SessionRegistryStoreTests {
    private func tempFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-registry-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    // MARK: - A4: CodexSessionStore round-trip (was untested)

    @Test
    func codexSessionStoreRoundTrips() throws {
        let fileURL = tempFile("session-terminals.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = CodexSessionStore(fileURL: fileURL)
        let records = [
            CodexTrackedSessionRecord(
                sessionID: "codex-1",
                title: "Codex · open-island",
                origin: .live,
                summary: "Working.",
                phase: .running,
                updatedAt: Date(timeIntervalSince1970: 1_000),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "codex ~/open-island",
                    terminalSessionID: "ghostty-codex"
                ),
                codexMetadata: CodexSessionMetadata(initialUserPrompt: "hi")
            ),
        ]

        try store.save(records)
        #expect(try store.load() == records)
    }

    @Test
    func loadReturnsEmptyWhenFileMissing() throws {
        let store = CodexSessionStore(fileURL: tempFile("does-not-exist.json"))
        #expect(try store.load().isEmpty)
    }

    // MARK: - A3: on-disk format compatibility

    /// A file written in the exact legacy format (ISO-8601 dates, arbitrary key
    /// order) must still decode — proves the shared store didn't change the wire
    /// format. This is hand-authored JSON, not produced by our encoder.
    @Test
    func decodesLegacyOnDiskFormat() throws {
        let fileURL = tempFile("cursor-session-registry.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        // ISO-8601 timestamp; keys deliberately not sorted.
        let legacy = """
        [
          {
            "summary": "Legacy record.",
            "sessionID": "cursor-legacy",
            "title": "Cursor · demo",
            "attachmentState": "attached",
            "phase": "running",
            "updatedAt": "2001-09-09T01:46:40Z"
          }
        ]
        """
        try Data(legacy.utf8).write(to: fileURL)

        let registry = CursorSessionRegistry(fileURL: fileURL)
        let records = try registry.load()
        #expect(records.count == 1)
        #expect(records.first?.sessionID == "cursor-legacy")
        // 2001-09-09T01:46:40Z == epoch 1_000_000_000
        #expect(records.first?.updatedAt == Date(timeIntervalSince1970: 1_000_000_000))
    }

    /// The shared store's output is itself valid ISO-8601 + sorted-keys JSON that
    /// round-trips through a plain decoder (guards the encoder policy).
    @Test
    func sharedStoreWritesISO8601SortedKeys() throws {
        let fileURL = tempFile("codex-session-registry.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let records = [
            CodexTrackedSessionRecord(
                sessionID: "s", title: "t", summary: "x", phase: .running,
                updatedAt: Date(timeIntervalSince1970: 1_000_000_000)
            ),
        ]
        try SessionRegistryStore.save(records, to: fileURL, fileManager: .default)

        let raw = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        #expect(raw.contains("2001-09-09T01:46:40Z"))   // .iso8601 date
        // sorted keys: phase before sessionID before summary before title before updatedAt
        let phaseIdx = try #require(raw.range(of: "\"phase\""))
        let sessionIdx = try #require(raw.range(of: "\"sessionID\""))
        #expect(phaseIdx.lowerBound < sessionIdx.lowerBound)

        let decoded: [CodexTrackedSessionRecord] = try SessionRegistryStore.load(
            from: fileURL, fileManager: .default
        )
        #expect(decoded == records)
    }
}
