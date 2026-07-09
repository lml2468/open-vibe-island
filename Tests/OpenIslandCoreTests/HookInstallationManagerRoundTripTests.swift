import Foundation
import Testing
@testable import OpenIslandCore

/// Manager-level install→uninstall round-trip + status characterization for the
/// three thinnest hook installation managers (slice `manager-roundtrip-tests`,
/// discovery finding #9 cluster B). These exercise the full manager orchestration
/// through the real filesystem (temp dir) — dir create, backup, atomic write,
/// manifest read/write, status derivation — which the pure-installer suites do
/// not cover. They are the regression net for the follow-on `ConfigManifestStore`
/// extraction, which relocates the shared private helpers these managers use.
struct HookInstallationManagerRoundTripTests {

    /// Creates a temp root with an executable fake hooks binary, runs `body` with
    /// (rootURL, agentDirectory, managedBinaryURL, fakeBuildBinaryURL), and cleans up.
    private static func withTempEnvironment(
        agentDirName: String,
        _ body: (URL, URL, URL, URL) throws -> Void
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-mgr-\(agentDirName)-\(UUID().uuidString)", isDirectory: true)
        let agentDirectory = rootURL.appendingPathComponent(agentDirName, isDirectory: true)
        let managedBinaryURL = rootURL
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")
        let buildBinaryURL = rootURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")

        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(
            at: buildBinaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fake-hook-binary".utf8).write(to: buildBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: buildBinaryURL.path)

        try body(rootURL, agentDirectory, managedBinaryURL, buildBinaryURL)
    }

    // MARK: - A1: Gemini manager round-trip

    @Test
    func geminiManagerRoundTripsInstallAndUninstall() throws {
        try Self.withTempEnvironment(agentDirName: ".gemini") { _, geminiDirectory, managedBinaryURL, buildBinaryURL in
            let manager = GeminiHookInstallationManager(
                geminiDirectory: geminiDirectory,
                managedHooksBinaryURL: managedBinaryURL
            )
            let settingsURL = geminiDirectory.appendingPathComponent("settings.json")
            let manifestURL = geminiDirectory.appendingPathComponent(GeminiHookInstallerManifest.fileName)

            // Install
            let installStatus = try manager.install(hooksBinaryURL: buildBinaryURL)
            #expect(installStatus.managedHooksPresent == true)
            #expect(installStatus.manifest != nil)
            #expect(FileManager.default.fileExists(atPath: settingsURL.path))
            #expect(FileManager.default.fileExists(atPath: manifestURL.path))

            let settingsData = try Data(contentsOf: settingsURL)
            let object = try JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
            let hooks = object?["hooks"] as? [String: Any]
            #expect(hooks?.keys.contains("SessionStart") == true)
            #expect(hooks?.keys.contains("Notification") == true)

            // Uninstall
            let uninstallStatus = try manager.uninstall()
            #expect(uninstallStatus.managedHooksPresent == false)
            #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
        }
    }

    // MARK: - A2: Kimi manager round-trip (TOML)

    @Test
    func kimiManagerRoundTripsInstallAndUninstall() throws {
        try Self.withTempEnvironment(agentDirName: ".kimi") { _, kimiDirectory, managedBinaryURL, buildBinaryURL in
            let manager = KimiHookInstallationManager(
                kimiDirectory: kimiDirectory,
                managedHooksBinaryURL: managedBinaryURL
            )
            let configURL = kimiDirectory.appendingPathComponent("config.toml")
            let manifestURL = kimiDirectory.appendingPathComponent(KimiHookInstallerManifest.fileName)

            // Install
            let installStatus = try manager.install(hooksBinaryURL: buildBinaryURL)
            #expect(installStatus.managedHooksPresent == true)
            #expect(installStatus.manifest != nil)
            #expect(FileManager.default.fileExists(atPath: configURL.path))
            #expect(FileManager.default.fileExists(atPath: manifestURL.path))

            let contents = try String(contentsOf: configURL, encoding: .utf8)
            #expect(contents.contains(KimiHookInstaller.markerComment))
            #expect(contents.contains("--source kimi"))

            // Uninstall
            let uninstallStatus = try manager.uninstall()
            #expect(uninstallStatus.managedHooksPresent == false)
            #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
        }
    }

    // MARK: - A3: Codex manager round-trip + feature-flag toggle (two files)

    @Test
    func codexManagerRoundTripsInstallAndUninstallTogglingFeatureFlag() throws {
        try Self.withTempEnvironment(agentDirName: ".codex") { _, codexDirectory, managedBinaryURL, buildBinaryURL in
            let manager = CodexHookInstallationManager(
                codexDirectory: codexDirectory,
                managedHooksBinaryURL: managedBinaryURL
            )
            let configURL = codexDirectory.appendingPathComponent("config.toml")
            let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
            let manifestURL = codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName)

            // Install — writes BOTH config.toml (feature flag) and hooks.json
            let installStatus = try manager.install(hooksBinaryURL: buildBinaryURL)
            #expect(installStatus.managedHooksPresent == true)
            #expect(installStatus.featureFlagEnabled == true)
            #expect(installStatus.manifest != nil)
            #expect(FileManager.default.fileExists(atPath: configURL.path))
            #expect(FileManager.default.fileExists(atPath: hooksURL.path))
            #expect(FileManager.default.fileExists(atPath: manifestURL.path))

            // Uninstall — no surviving user hooks → the gated
            // disableCodexHooksFeatureIfManaged fires, toggling the flag false.
            let uninstallStatus = try manager.uninstall()
            #expect(uninstallStatus.managedHooksPresent == false)
            #expect(uninstallStatus.featureFlagEnabled == false)
            #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
        }
    }
}
