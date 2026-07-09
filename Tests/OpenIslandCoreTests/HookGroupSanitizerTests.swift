import Foundation
import Testing
@testable import OpenIslandCore

/// Direct characterization of the shared `HookGroupSanitizer` walk plus
/// behavior-preservation round-trips for the two installers that delegate to it
/// (slice `dedup-sanitize-mutators`, discovery finding #9 cluster B).
///
/// A1/A2 pin the mechanical walk with a stub `isManaged` closure (no gating).
/// A3 proves each installer's DIVERGENT leaf still drives deletion through the
/// shared walk — Claude via its legacy marker, Codex via its statusMessage.
struct HookGroupSanitizerTests {

    // A hook is "managed" iff its command equals this sentinel — a pure stub so
    // A1/A2 exercise only the traversal, never real gating.
    private static let managedSentinel = "MANAGED"
    private static func stubIsManaged(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String) == managedSentinel
    }

    private static func hook(_ command: String) -> [String: Any] {
        ["type": "command", "command": command]
    }

    private static func group(_ commands: [String], matcher: String? = nil) -> [String: Any] {
        var g: [String: Any] = ["hooks": commands.map { hook($0) }]
        if let matcher { g["matcher"] = matcher }
        return g
    }

    // MARK: - A1: sanitize reproduces the partial-survival walk

    @Test
    func sanitizeKeepsNonManagedHookAndDropsManagedWithinAGroup() {
        let groups: [Any] = [Self.group(["MANAGED", "user-hook"], matcher: "*")]
        let result = HookGroupSanitizer.sanitize(groups: groups, isManaged: Self.stubIsManaged)

        #expect(result.count == 1)
        guard let survivingGroup = result.first else {
            #expect(Bool(false), "expected one surviving group")
            return
        }
        let survivingHooks = survivingGroup["hooks"] as? [[String: Any]] ?? []
        #expect(survivingHooks.count == 1)
        #expect(survivingHooks.first?["command"] as? String == "user-hook")
        // The group's other keys are preserved.
        #expect(survivingGroup["matcher"] as? String == "*")
    }

    @Test
    func sanitizeDropsAGroupWhoseHooksAllMatch() {
        let groups: [Any] = [Self.group(["MANAGED", "MANAGED"])]
        let result = HookGroupSanitizer.sanitize(groups: groups, isManaged: Self.stubIsManaged)
        #expect(result.isEmpty)
    }

    @Test
    func sanitizeDropsNonDictElementsAndGroupsWithoutHooks() {
        let groups: [Any] = ["not-a-dict", 42, ["matcher": "*"] as [String: Any]]
        let result = HookGroupSanitizer.sanitize(groups: groups, isManaged: Self.stubIsManaged)
        // Non-dict elements dropped; the dict has no "hooks" → empty → dropped.
        #expect(result.isEmpty)
    }

    @Test
    func sanitizeKeepsAFullyUserGroupIntact() {
        let groups: [Any] = [Self.group(["a", "b"])]
        let result = HookGroupSanitizer.sanitize(groups: groups, isManaged: Self.stubIsManaged)
        #expect(result.count == 1)
        #expect((result.first?["hooks"] as? [[String: Any]])?.count == 2)
    }

    // MARK: - A2: containsManagedHook reproduces the two-level contains

    @Test
    func containsManagedHookTrueWhenAnyGroupHasAManagedHook() {
        let groups: [Any] = [Self.group(["user"]), Self.group(["user2", "MANAGED"])]
        #expect(HookGroupSanitizer.containsManagedHook(in: groups, isManaged: Self.stubIsManaged))
    }

    @Test
    func containsManagedHookFalseForAllUserGroups() {
        let groups: [Any] = [Self.group(["user"]), Self.group(["user2"])]
        #expect(!HookGroupSanitizer.containsManagedHook(in: groups, isManaged: Self.stubIsManaged))
    }

    @Test
    func containsManagedHookFalseForEmptyOrMalformedGroups() {
        let groups: [Any] = ["nope", ["matcher": "*"] as [String: Any]]
        #expect(!HookGroupSanitizer.containsManagedHook(in: groups, isManaged: Self.stubIsManaged))
    }

    // MARK: - A3: each installer's divergent leaf still drives deletion

    /// Claude uses its legacy-marker leaf. A hook whose command carries the
    /// Open Island marker + `--source claude` must be removed on uninstall while
    /// a foreign hook in the same event survives.
    @Test
    func claudeUninstallRemovesLegacyMarkerHookAndKeepsForeign() throws {
        let managed = "/opt/openislandhooks/hook --source claude"
        let foreign = "/usr/local/bin/my-own-hook"
        let root: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    ["matcher": "*", "hooks": [
                        ["type": "command", "command": managed],
                        ["type": "command", "command": foreign],
                    ]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: root)
        let mutation = try ClaudeHookInstaller.uninstallSettingsJSON(existingData: data, managedCommand: nil)

        #expect(mutation.changed)
        let out = try JSONSerialization.jsonObject(with: mutation.contents ?? Data()) as? [String: Any]
        let hooks = out?["hooks"] as? [String: Any]
        let groups = hooks?["PreToolUse"] as? [[String: Any]] ?? []
        let survivingCommands = groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        #expect(survivingCommands == [foreign])
    }

    /// Codex uses its statusMessage-first leaf. A hook with the managed
    /// statusMessage but a FOREIGN command must still be removed on uninstall —
    /// this is the distinguishing behavior of the Codex leaf.
    @Test
    func codexUninstallRemovesStatusMessageManagedHookWithForeignCommand() throws {
        let statusManaged: [String: Any] = [
            "type": "command",
            "command": "/some/other/binary",
            "statusMessage": CodexHookInstaller.managedStatusMessage,
        ]
        let foreign: [String: Any] = ["type": "command", "command": "/usr/local/bin/mine"]
        // Codex uninstall only walks its own eventSpecs; "Stop" is one of them.
        let root: [String: Any] = [
            "hooks": ["Stop": [["hooks": [statusManaged, foreign]]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: root)
        let mutation = try CodexHookInstaller.uninstallHooksJSON(existingData: data, managedCommand: nil)

        #expect(mutation.changed)
        let out = try JSONSerialization.jsonObject(with: mutation.contents ?? Data()) as? [String: Any]
        let hooks = out?["hooks"] as? [String: Any]
        let groups = hooks?["Stop"] as? [[String: Any]] ?? []
        let survivingCommands = groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        #expect(survivingCommands == ["/usr/local/bin/mine"])
    }

    /// Claude install→uninstall round-trip returns to a clean state (no managed
    /// hooks remain), exercising sanitizeForInstall + sanitize + containsManagedHook.
    @Test
    func claudeInstallUninstallRoundTripLeavesNoManagedHooks() throws {
        let command = ClaudeHookInstaller.hookCommand(for: "/opt/openislandhooks/hook")
        let installed = try ClaudeHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command)
        #expect(installed.managedHooksPresent)

        let uninstalled = try ClaudeHookInstaller.uninstallSettingsJSON(
            existingData: installed.contents,
            managedCommand: command
        )
        // Every managed hook removed → file reduces to nil (nothing else present).
        #expect(uninstalled.contents == nil)
        #expect(uninstalled.changed)
    }
}
