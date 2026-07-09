import Testing
import Foundation
@testable import OpenIslandApp
import OpenIslandCore

/// Regression coverage for the rediscovery Gemini-metadata merge bug (slice
/// `missing-gemini-metadata-merge`): `SessionDiscoveryCoordinator.merge` reconciled
/// Codex/Claude/OpenCode/Cursor metadata but omitted Gemini, so a rediscovered
/// Gemini session's metadata was dropped. These pin the fixed merge behavior.
@MainActor
struct GeminiMetadataMergeTests {

    private func session(
        id: String,
        updatedAt: Date,
        geminiMetadata: GeminiSessionMetadata? = nil
    ) -> AgentSession {
        var s = AgentSession(
            id: id,
            title: "T-\(id)",
            tool: .geminiCLI,
            origin: .live,
            attachmentState: .detached,
            phase: .running,
            summary: "s",
            updatedAt: updatedAt
        )
        s.geminiMetadata = geminiMetadata
        return s
    }

    // A1: rediscovery preserves BOTH existing and newly-discovered Gemini fields.
    @Test
    func mergePreservesExistingAndAddsDiscoveredGeminiFields() {
        let t0 = Date(timeIntervalSince1970: 5_000)
        let existing = session(
            id: "g1",
            updatedAt: t0,
            geminiMetadata: GeminiSessionMetadata(initialUserPrompt: "hello")
        )
        let c = SessionDiscoveryCoordinator()
        c.stateAccessor = { SessionState(sessions: [existing]) }

        let discovered = session(
            id: "g1",
            updatedAt: t0.addingTimeInterval(10),
            geminiMetadata: GeminiSessionMetadata(
                transcriptPath: "/tmp/g.jsonl",
                lastAssistantMessage: "hi there"
            )
        )

        let merged = c.mergeDiscoveredSessions([discovered]).first { $0.id == "g1" }
        let gm = merged?.geminiMetadata
        #expect(gm?.initialUserPrompt == "hello")          // existing preserved
        #expect(gm?.transcriptPath == "/tmp/g.jsonl")      // discovered carried through (the bug)
        #expect(gm?.lastAssistantMessage == "hi there")    // discovered carried through
    }

    // A2: existing Gemini metadata is not lost when discovered has none.
    @Test
    func mergeKeepsExistingGeminiWhenDiscoveredHasNone() {
        let t0 = Date(timeIntervalSince1970: 6_000)
        let existing = session(
            id: "g2",
            updatedAt: t0,
            geminiMetadata: GeminiSessionMetadata(initialUserPrompt: "keep me")
        )
        let c = SessionDiscoveryCoordinator()
        c.stateAccessor = { SessionState(sessions: [existing]) }

        let discovered = session(id: "g2", updatedAt: t0.addingTimeInterval(10), geminiMetadata: nil)

        let merged = c.mergeDiscoveredSessions([discovered]).first { $0.id == "g2" }
        #expect(merged?.geminiMetadata?.initialUserPrompt == "keep me")
    }

    // A3: nil/empty handling matches the other mergers (both nil → nil).
    @Test
    func mergeYieldsNilWhenBothGeminiAreNil() {
        let t0 = Date(timeIntervalSince1970: 7_000)
        let existing = session(id: "g3", updatedAt: t0, geminiMetadata: nil)
        let c = SessionDiscoveryCoordinator()
        c.stateAccessor = { SessionState(sessions: [existing]) }

        let discovered = session(id: "g3", updatedAt: t0.addingTimeInterval(10), geminiMetadata: nil)

        let merged = c.mergeDiscoveredSessions([discovered]).first { $0.id == "g3" }
        #expect(merged?.geminiMetadata == nil)
    }
}
