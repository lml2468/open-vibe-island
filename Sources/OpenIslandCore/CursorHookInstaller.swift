import Foundation

public struct CursorHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-cursor-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct CursorHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public enum CursorHookInstallerError: Error, LocalizedError {
    case invalidHooksJSON

    public var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            "The existing Cursor hooks.json is not valid JSON."
        }
    }
}

public enum CursorHookInstaller {
    private static let hookEvents: [String] = [
        "beforeSubmitPrompt",
        "beforeShellExecution",
        "beforeMCPExecution",
        "beforeReadFile",
        "afterFileEdit",
        "stop",
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(ShellQuoting.quote(binaryPath)) --source cursor"
    }

    public static func installHooksJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> CursorHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        // Only set the default schema version when the user hasn't authored one;
        // never clobber an existing top-level `version`.
        if rootObject["version"] == nil {
            rootObject["version"] = 1
        }

        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]

        for event in hookEvents {
            var entries = hooksObject[event] as? [[String: Any]] ?? []
            entries = entries.filter { !isManagedHook($0, managedCommand: hookCommand) }
            entries.append(["command": hookCommand])
            hooksObject[event] = entries
        }

        rootObject["hooks"] = hooksObject
        let data = try JSONConfigSerialization.serialize(rootObject)

        return CursorHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallHooksJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> CursorHookFileMutation {
        guard let existingData else {
            return CursorHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for event in hookEvents {
            let entries = hooksObject[event] as? [[String: Any]] ?? []
            let filtered = entries.filter { !isManagedHook($0, managedCommand: managedCommand) }

            if filtered.count != entries.count {
                mutated = true
            }

            if filtered.isEmpty {
                hooksObject.removeValue(forKey: event)
            } else {
                hooksObject[event] = filtered
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        // Only drop the file when it is genuinely empty. A remaining top-level
        // `version` (or any other key) may be user-authored — install no longer
        // forces `version`, so we can't distinguish "ours" from the user's and
        // must not delete it. Preserving a stray `{ "version": 1 }` is harmless;
        // wiping a user's config is not.
        let contents = rootObject.isEmpty ? nil : try JSONConfigSerialization.serialize(rootObject)

        return CursorHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        try JSONConfigSerialization.loadRootObject(from: data, invalidError: CursorHookInstallerError.invalidHooksJSON)
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        guard let command = hook["command"] as? String else { return false }

        if let managedCommand, command == managedCommand {
            return true
        }

        return isOpenIslandCursorHookCommand(command)
    }

    static func isOpenIslandCursorHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return (normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks"))
            && normalized.contains("cursor")
    }
}
