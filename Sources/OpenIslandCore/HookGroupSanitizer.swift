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
    // RED STUB — returns wrong values so the failing-first tests compile and
    // fail on assertion. Replaced in Green.
    static func sanitize(
        groups: [Any],
        isManaged: ([String: Any]) -> Bool
    ) -> [[String: Any]] {
        []
    }

    static func containsManagedHook(
        in groups: [Any],
        isManaged: ([String: Any]) -> Bool
    ) -> Bool {
        false
    }
}
