import Foundation

/// Shared array-walking mechanics for the group→hooks JSON installers
/// (Claude, Codex), extracted from their byte-identical `sanitize` /
/// `sanitizeForInstall` / `containsManagedHook` copies (slice
/// `dedup-sanitize-mutators`, discovery finding #9 cluster B).
///
/// Only the *mechanical* walk lives here; the safety-critical decision of
/// whether a given hook is Open-Island-managed stays in each installer's own
/// leaf predicate, passed in as `isManaged`. This preserves the divergent,
/// locally-auditable gating that `installer-config-safety` requires while
/// removing the duplicated traversal.
enum HookGroupSanitizer {
    /// Filters managed hooks out of each group, keeping the group (and its other
    /// keys) when non-managed hooks survive, and dropping a group entirely when
    /// its surviving hooks would be empty. Non-dictionary elements are dropped.
    static func sanitize(
        groups: [Any],
        isManaged: ([String: Any]) -> Bool
    ) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManaged(hook) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    /// True iff some group contains some hook the `isManaged` closure matches.
    static func containsManagedHook(
        in groups: [Any],
        isManaged: ([String: Any]) -> Bool
    ) -> Bool {
        groups.contains { item in
            guard let group = item as? [String: Any],
                  let hooks = group["hooks"] as? [Any] else {
                return false
            }

            return hooks.contains { hook in
                guard let hook = hook as? [String: Any] else {
                    return false
                }

                return isManaged(hook)
            }
        }
    }
}
