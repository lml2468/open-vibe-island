import Foundation

/// Shared backup helper for the config-file installers.
///
/// Every installer that mutates a third-party config file (`~/.claude`,
/// `~/.codex`, `~/.cursor`, `~/.config/opencode`, …) takes a timestamped copy
/// first so setup stays reversible. This type centralizes that logic — it used
/// to be copy-pasted across seven managers — and adds bounded retention so the
/// backups can't accumulate without limit in the user's config directories.
///
/// Filename scheme (unchanged from the original per-manager copies, so backups
/// written by older versions are still recognized and pruned):
/// `<name>.backup.<ISO8601, ':' → '-'>` alongside the original file.
public enum ConfigBackup {
    /// Default number of most-recent backups kept per target file.
    public static let defaultRetention = 5

    /// The extension suffix that marks an Open Island backup: `backup.<timestamp>`.
    static let backupInfix = "backup."

    /// Copy `url` to a timestamped sibling, then prune older backups so at most
    /// `retention` most-recent copies remain for that file. No-op if `url` does
    /// not exist. Pruning failures are non-fatal — the backup itself is what
    /// matters for reversibility.
    public static func backup(
        _ url: URL,
        retention: Int = defaultRetention,
        fileManager: FileManager = .default,
        now: Date = .now
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.appendingPathExtension("\(backupInfix)\(timestamp)")

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)

        pruneOldBackups(of: url, keeping: retention, fileManager: fileManager)
    }

    /// Delete all but the `keeping` most-recent Open Island backups of `url`.
    /// Best-effort: any deletion error is ignored so a prune failure never
    /// blocks an install.
    static func pruneOldBackups(
        of url: URL,
        keeping: Int,
        fileManager: FileManager = .default
    ) {
        let directory = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        // Match "<base>.backup.<timestamp>" — the ISO8601 timestamp sorts
        // lexicographically in chronological order, so a plain name sort orders
        // oldest → newest.
        let prefix = "\(base).\(backupInfix)"

        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let backups = entries
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard backups.count > keeping else {
            return
        }

        for stale in backups.dropLast(keeping) {
            try? fileManager.removeItem(at: stale)
        }
    }
}
