import Foundation
import Testing
@testable import OpenIslandCore

/// Covers the installer-safety slice (arch-quality-audit #7, #20):
/// bounded backup retention via the shared ConfigBackup helper, and OpenCode
/// refusing to clobber a malformed config.json.
struct InstallerSafetyTests {
    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-installer-safety-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - #20 bounded backups

    @Test
    func configBackupCreatesTimestampedCopy() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("config.json")
        try Data("original".utf8).write(to: target)

        try ConfigBackup.backup(target, now: Date(timeIntervalSince1970: 1_000))

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("config.json.backup.") }
        #expect(backups.count == 1)
        let backupData = try Data(contentsOf: dir.appendingPathComponent(backups[0]))
        #expect(String(decoding: backupData, as: UTF8.self) == "original")
    }

    @Test
    func configBackupIsNoOpWhenSourceMissing() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("absent.json")

        try ConfigBackup.backup(target)

        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(entries.isEmpty)
    }

    @Test
    func configBackupPrunesToRetentionLimit() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("config.json")
        try Data("v0".utf8).write(to: target)

        // Ten changed writes, each backed up with a distinct, increasing
        // timestamp (the filename timestamp is what pruning sorts on).
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<10 {
            try Data("v\(i)".utf8).write(to: target)
            try ConfigBackup.backup(target, retention: 5, now: base.addingTimeInterval(Double(i) * 60))
        }

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("config.json.backup.") }
            .sorted()
        #expect(backups.count == 5)
        // The five kept must be the most-recent (largest timestamps) — i.e. the
        // last five we wrote. Oldest pruned: the first five.
        let allTimestamps = (0..<10).map { base.addingTimeInterval(Double($0) * 60) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let keptStamps = Set(allTimestamps.suffix(5).map {
            formatter.string(from: $0).replacingOccurrences(of: ":", with: "-")
        })
        for name in backups {
            let stamp = name.replacingOccurrences(of: "config.json.backup.", with: "")
            #expect(keptStamps.contains(stamp))
        }
    }

    // MARK: - #7 OpenCode must not clobber a malformed config

    @Test
    func openCodeInstallThrowsOnMalformedConfigAndLeavesItUntouched() throws {
        let configDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: configDir) }
        let configURL = configDir.appendingPathComponent("config.json")
        let original = "this is not json { ["
        try Data(original.utf8).write(to: configURL)

        let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: configDir)

        #expect(throws: OpenCodePluginInstallationManager.OpenCodePluginInstallerError.self) {
            _ = try manager.install(pluginSourceData: Data("// plugin".utf8))
        }

        // The malformed file must be byte-for-byte unchanged.
        let after = try Data(contentsOf: configURL)
        #expect(String(decoding: after, as: UTF8.self) == original)
    }

    @Test
    func openCodeInstallPreservesExistingValidConfig() throws {
        let configDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: configDir) }
        let configURL = configDir.appendingPathComponent("config.json")
        try Data(#"{"theme":"dark","plugin":["existing/plugin.js"]}"#.utf8).write(to: configURL)

        let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: configDir)

        _ = try manager.install(pluginSourceData: Data("// plugin".utf8))

        let data = try Data(contentsOf: configURL)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // User's unrelated key survives; both the pre-existing plugin and ours are present.
        #expect(object["theme"] as? String == "dark")
        let plugins = object["plugin"] as! [String]
        #expect(plugins.contains("existing/plugin.js"))
        #expect(plugins.contains { $0.hasSuffix("/open-island.js") })
    }
}
