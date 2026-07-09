import Foundation

/// Shared marker-substring atoms for Open Island managed/legacy hook detection.
/// The per-agent gating (source flag vs bare name; which families count) stays in
/// each installer — only the brand-alias literals are centralized so a new alias
/// is added in one place. Callers pass an already-lowercased string.
enum OpenIslandHookMarkers {
    /// True if the (already-lowercased) command contains an Open Island hooks-CLI
    /// marker (`openislandhooks` / `vibeislandhooks`).
    static func hasHooksMarker(_ normalized: String) -> Bool {
        normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks")
    }

    /// True if the (already-lowercased) command contains an Open Island bridge
    /// marker (`open-island-bridge` / `vibe-island-bridge`).
    static func hasBridgeMarker(_ normalized: String) -> Bool {
        normalized.contains("open-island-bridge") || normalized.contains("vibe-island-bridge")
    }
}
