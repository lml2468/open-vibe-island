import Testing
@testable import OpenIslandCore

/// Marker-atom helper + per-predicate truth-table characterization for the hook
/// command-detection predicates (slice `dedup-installer-hookmarkers`, discovery
/// finding #9 cluster B). A2's per-predicate tests pin each installer's current
/// truth table so the marker extraction stays behavior-neutral.
struct OpenIslandHookMarkersTests {

    // MARK: - A1: the shared marker atoms

    @Test
    func hasHooksMarkerMatchesBothAliases() {
        #expect(OpenIslandHookMarkers.hasHooksMarker("x openislandhooks y"))
        #expect(OpenIslandHookMarkers.hasHooksMarker("x vibeislandhooks y"))
        #expect(OpenIslandHookMarkers.hasHooksMarker("no markers here") == false)
        #expect(OpenIslandHookMarkers.hasHooksMarker("open-island-bridge") == false) // bridge != hooks
    }

    @Test
    func hasBridgeMarkerMatchesBothAliases() {
        #expect(OpenIslandHookMarkers.hasBridgeMarker("x open-island-bridge y"))
        #expect(OpenIslandHookMarkers.hasBridgeMarker("x vibe-island-bridge y"))
        #expect(OpenIslandHookMarkers.hasBridgeMarker("no markers here") == false)
        #expect(OpenIslandHookMarkers.hasBridgeMarker("openislandhooks") == false) // hooks != bridge
    }

    // MARK: - A2: per-predicate truth tables (behavior-neutrality guard)

    @Test
    func claudePredicateTruthTable() {
        // hooks marker requires --source claude; bridge marker requires bare "claude".
        #expect(ClaudeHookInstaller.isLegacyOpenIslandHookCommand("openislandhooks --source claude"))
        #expect(ClaudeHookInstaller.isLegacyOpenIslandHookCommand("vibeislandhooks --source claude"))
        #expect(ClaudeHookInstaller.isLegacyOpenIslandHookCommand("openislandhooks") == false) // no --source claude
        #expect(ClaudeHookInstaller.isLegacyOpenIslandHookCommand("open-island-bridge claude")) // bridge + bare claude
        #expect(ClaudeHookInstaller.isLegacyOpenIslandHookCommand("open-island-bridge") == false) // bridge, no claude
        #expect(ClaudeHookInstaller.isLegacyOpenIslandHookCommand("nothing") == false)
    }

    @Test
    func codexPredicateTruthTable() {
        // Ungated: any marker of either family matches.
        #expect(CodexHookInstaller.isLegacyOpenIslandHookCommand("openislandhooks"))
        #expect(CodexHookInstaller.isLegacyOpenIslandHookCommand("vibeislandhooks"))
        #expect(CodexHookInstaller.isLegacyOpenIslandHookCommand("open-island-bridge"))
        #expect(CodexHookInstaller.isLegacyOpenIslandHookCommand("vibe-island-bridge"))
        #expect(CodexHookInstaller.isLegacyOpenIslandHookCommand("nothing") == false)
    }

    @Test
    func cursorPredicateTruthTable() {
        // hooks marker AND bare "cursor"; bridge family ignored.
        #expect(CursorHookInstaller.isOpenIslandCursorHookCommand("openislandhooks cursor"))
        #expect(CursorHookInstaller.isOpenIslandCursorHookCommand("vibeislandhooks --source cursor"))
        #expect(CursorHookInstaller.isOpenIslandCursorHookCommand("openislandhooks") == false) // no "cursor"
        #expect(CursorHookInstaller.isOpenIslandCursorHookCommand("open-island-bridge cursor") == false) // bridge ignored
        #expect(CursorHookInstaller.isOpenIslandCursorHookCommand("nothing") == false)
    }

    @Test
    func geminiPredicateTruthTable() {
        // hooks marker AND bare "gemini"; bridge family ignored.
        #expect(GeminiHookInstaller.isOpenIslandGeminiHookCommand("openislandhooks gemini"))
        #expect(GeminiHookInstaller.isOpenIslandGeminiHookCommand("vibeislandhooks --source gemini"))
        #expect(GeminiHookInstaller.isOpenIslandGeminiHookCommand("openislandhooks") == false) // no "gemini"
        #expect(GeminiHookInstaller.isOpenIslandGeminiHookCommand("open-island-bridge gemini") == false) // bridge ignored
        #expect(GeminiHookInstaller.isOpenIslandGeminiHookCommand("nothing") == false)
    }

    @Test
    func kimiPredicateTruthTable() {
        // requires --source kimi, then any marker of either family.
        #expect(KimiHookInstaller.isLegacyOpenIslandHookCommand("openislandhooks --source kimi"))
        #expect(KimiHookInstaller.isLegacyOpenIslandHookCommand("open-island-bridge --source kimi"))
        #expect(KimiHookInstaller.isLegacyOpenIslandHookCommand("openislandhooks") == false) // no --source kimi
        #expect(KimiHookInstaller.isLegacyOpenIslandHookCommand("--source kimi only") == false) // no marker
        #expect(KimiHookInstaller.isLegacyOpenIslandHookCommand("nothing") == false)
    }
}
