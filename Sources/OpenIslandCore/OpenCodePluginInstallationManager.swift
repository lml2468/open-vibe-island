import Foundation

public struct OpenCodePluginInstallationStatus: Equatable, Sendable {
    public var openCodeConfigDirectory: URL
    public var pluginsDirectory: URL
    public var configURL: URL
    public var pluginFileURL: URL
    public var manifestURL: URL
    public var pluginFilePresent: Bool
    public var pluginRegistered: Bool
    public var manifest: OpenCodePluginInstallerManifest?

    public var isInstalled: Bool {
        pluginFilePresent && pluginRegistered
    }

    public init(
        openCodeConfigDirectory: URL,
        pluginsDirectory: URL,
        configURL: URL,
        pluginFileURL: URL,
        manifestURL: URL,
        pluginFilePresent: Bool,
        pluginRegistered: Bool,
        manifest: OpenCodePluginInstallerManifest?
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.pluginsDirectory = pluginsDirectory
        self.configURL = configURL
        self.pluginFileURL = pluginFileURL
        self.manifestURL = manifestURL
        self.pluginFilePresent = pluginFilePresent
        self.pluginRegistered = pluginRegistered
        self.manifest = manifest
    }
}

public struct OpenCodePluginInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-opencode-plugin-install.json"

    public var pluginPath: String
    public var installedAt: Date

    public init(pluginPath: String, installedAt: Date = .now) {
        self.pluginPath = pluginPath
        self.installedAt = installedAt
    }
}

public final class OpenCodePluginInstallationManager: @unchecked Sendable {
    public static let pluginFileName = "open-island.js"

    public enum OpenCodePluginInstallerError: Error, LocalizedError, Equatable {
        /// `config.json` exists but is not a decodable JSON object. We refuse to
        /// overwrite it — doing so would destroy the user's OpenCode config.
        case invalidConfigJSON

        public var errorDescription: String? {
            switch self {
            case .invalidConfigJSON:
                "~/.config/opencode/config.json exists but is not valid JSON; refusing to overwrite it."
            }
        }
    }

    public let openCodeConfigDirectory: URL
    private let fileManager: FileManager

    public init(
        openCodeConfigDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.fileManager = fileManager
    }

    private var pluginsDirectory: URL {
        openCodeConfigDirectory.appendingPathComponent("plugins", isDirectory: true)
    }

    private var pluginFileURL: URL {
        pluginsDirectory.appendingPathComponent(Self.pluginFileName)
    }

    private var configURL: URL {
        openCodeConfigDirectory.appendingPathComponent("config.json")
    }

    private var manifestURL: URL {
        openCodeConfigDirectory.appendingPathComponent(OpenCodePluginInstallerManifest.fileName)
    }

    public func status() throws -> OpenCodePluginInstallationStatus {
        let pluginPresent = fileManager.fileExists(atPath: pluginFileURL.path)
        let registered = isPluginRegistered()
        let manifest = try loadManifest()

        return OpenCodePluginInstallationStatus(
            openCodeConfigDirectory: openCodeConfigDirectory,
            pluginsDirectory: pluginsDirectory,
            configURL: configURL,
            pluginFileURL: pluginFileURL,
            manifestURL: manifestURL,
            pluginFilePresent: pluginPresent,
            pluginRegistered: registered,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(pluginSourceData: Data) throws -> OpenCodePluginInstallationStatus {
        try fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)

        // Write the JS plugin file
        try pluginSourceData.write(to: pluginFileURL, options: .atomic)

        // Register in config.json
        try registerPluginInConfig()

        // Write manifest
        let manifest = OpenCodePluginInstallerManifest(pluginPath: pluginFileURL.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status()
    }

    @discardableResult
    public func uninstall() throws -> OpenCodePluginInstallationStatus {
        // Remove plugin file
        if fileManager.fileExists(atPath: pluginFileURL.path) {
            try fileManager.removeItem(at: pluginFileURL)
        }

        // Remove from config.json
        try unregisterPluginFromConfig()

        // Remove manifest
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    // MARK: - Config.json manipulation

    private func pluginFileReference() -> String {
        "file://\(pluginFileURL.path)"
    }

    private func isPluginRegistered() -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugin"] as? [String] else {
            return false
        }

        let ref = pluginFileReference()
        return plugins.contains { $0 == ref || $0.hasSuffix("/\(Self.pluginFileName)") }
    }

    private func registerPluginInConfig() throws {
        let ref = pluginFileReference()

        var json: [String: Any]
        if fileManager.fileExists(atPath: configURL.path) {
            // The file exists: it MUST parse as a JSON object, otherwise we would
            // clobber the user's config by writing back only our own block.
            // Match the other installers, which throw rather than reset.
            guard let data = try? Data(contentsOf: configURL),
                  let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw OpenCodePluginInstallerError.invalidConfigJSON
            }
            json = existing
        } else {
            // No config yet: start fresh.
            json = [:]
        }

        var plugins = (json["plugin"] as? [String]) ?? []

        // Remove any existing Open Island plugin references
        plugins.removeAll { $0 == ref || $0.hasSuffix("/\(Self.pluginFileName)") }
        plugins.append(ref)

        json["plugin"] = plugins

        if fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        let outputData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: configURL, options: .atomic)
    }

    private func unregisterPluginFromConfig() throws {
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var plugins = json["plugin"] as? [String] else {
            return
        }

        let ref = pluginFileReference()
        let before = plugins.count
        plugins.removeAll { $0 == ref || $0.hasSuffix("/\(Self.pluginFileName)") }

        guard plugins.count != before else {
            return
        }

        if fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if plugins.isEmpty {
            json.removeValue(forKey: "plugin")
        } else {
            json["plugin"] = plugins
        }

        let outputData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: configURL, options: .atomic)
    }

    // MARK: - Helpers

    private func loadManifest() throws -> OpenCodePluginInstallerManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OpenCodePluginInstallerManifest.self, from: data)
    }

    private func backupFile(at url: URL) throws {
        try ConfigBackup.backup(url, fileManager: fileManager)
    }
}
