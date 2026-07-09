import Foundation

/// Shared marker-substring atoms for Open Island managed/legacy hook detection.
/// The per-agent gating (source flag vs bare name; which families count) stays in
/// each installer — only the brand-alias literals are centralized so a new alias
/// is added in one place. Callers pass an already-lowercased string.
enum OpenIslandHookMarkers {
    /// STUB (Red): real matching filled in during Green.
    static func hasHooksMarker(_ normalized: String) -> Bool {
        false
    }

    /// STUB (Red): real matching filled in during Green.
    static func hasBridgeMarker(_ normalized: String) -> Bool {
        false
    }
}
