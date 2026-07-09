import Foundation
import Testing
@testable import OpenIslandCore

/// Direct characterization of the shared `ConfigManifestStore` persistence +
/// binary-resolution helpers (slice `config-manifest-store`, discovery finding #9
/// cluster B). The manager round-trip suites (HookInstallationManagerRoundTripTests
/// + Claude/Cursor manager tests) provide the behavior-neutrality proof for the
/// delegation; these pin the extracted helper directly.
struct ConfigManifestStoreTests {

    private static func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("config-manifest-store-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - A1: write → load round-trips a Codable, with the expected on-disk form

    @Test
    func writeThenLoadRoundTripsAndEmitsSortedISOJSON() throws {
        let dir = Self.tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("manifest.json")
        // A manifest with a Date field so iso8601 encoding is exercised.
        let manifest = ClaudeHookInstallerManifest(
            hookCommand: "/opt/openislandhooks/hook --source claude",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try ConfigManifestStore.write(manifest, to: url)

        let loaded: ClaudeHookInstallerManifest? = try ConfigManifestStore.load(
            at: url,
            fileManager: .default
        )
        #expect(loaded == manifest)

        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // pretty-printed (multi-line) + sorted keys (hookCommand before installedAt)
        #expect(raw.contains("\n"))
        let hookIdx = raw.range(of: "hookCommand")
        let installedIdx = raw.range(of: "installedAt")
        #expect(hookIdx != nil && installedIdx != nil)
        if let hookIdx, let installedIdx {
            #expect(hookIdx.lowerBound < installedIdx.lowerBound)
        }
        // iso8601 date form (contains a 'T' and 'Z' from the 2023 timestamp).
        #expect(raw.contains("2023-11-14T"))
    }

    // MARK: - A2: load returns nil for a missing file, throws for corrupt data

    @Test
    func loadReturnsNilForMissingFile() throws {
        let dir = Self.tempDir()
        // dir intentionally not created — the file is absent.
        let url = dir.appendingPathComponent("does-not-exist.json")
        let loaded: ClaudeHookInstallerManifest? = try ConfigManifestStore.load(
            at: url,
            fileManager: .default
        )
        #expect(loaded == nil)
    }

    @Test
    func loadThrowsForCorruptData() throws {
        let dir = Self.tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("corrupt.json")
        try Data("not valid json {{".utf8).write(to: url)

        #expect(throws: (any Error).self) {
            let _: ClaudeHookInstallerManifest? = try ConfigManifestStore.load(
                at: url,
                fileManager: .default
            )
        }
    }

    // MARK: - A3: resolvedBinaryURL matches the managers' resolution

    @Test
    func resolvedBinaryURLReturnsStandardizedExplicitURLWhenGiven() {
        let explicit = URL(fileURLWithPath: "/tmp/../tmp/build/OpenIslandHooks")
        let managed = URL(fileURLWithPath: "/managed/OpenIslandHooks")
        let resolved = ConfigManifestStore.resolvedBinaryURL(
            managedBinaryURL: managed,
            explicitURL: explicit,
            fileManager: .default
        )
        #expect(resolved == explicit.standardizedFileURL)
    }

    @Test
    func resolvedBinaryURLReturnsManagedWhenExecutableElseNil() throws {
        let dir = Self.tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let managed = dir.appendingPathComponent("OpenIslandHooks")

        // Not present yet → nil.
        #expect(ConfigManifestStore.resolvedBinaryURL(
            managedBinaryURL: managed,
            explicitURL: nil,
            fileManager: .default
        ) == nil)

        // Present but not executable → nil.
        try Data("bin".utf8).write(to: managed)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: managed.path)
        #expect(ConfigManifestStore.resolvedBinaryURL(
            managedBinaryURL: managed,
            explicitURL: nil,
            fileManager: .default
        ) == nil)

        // Executable → returns managed.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managed.path)
        #expect(ConfigManifestStore.resolvedBinaryURL(
            managedBinaryURL: managed,
            explicitURL: nil,
            fileManager: .default
        ) == managed)
    }
}
