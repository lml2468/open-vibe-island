import Foundation
import Testing
@testable import OpenIslandCore

/// Direct reducer characterization for the 5 `SessionState.apply` metadata arms
/// (slice `reducer-metadata-arm-tests`, discovery finding #10). Each arm: a
/// non-empty payload sets the agent's metadata, an empty payload nils it, the
/// caller-supplied timestamp lands on `updatedAt`, and an unknown sessionID is a
/// no-op. These pin the behavior the follow-on arm-collapse (slice A) must
/// preserve; they pass on the current tree.
struct ReducerMetadataArmTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000)
    private static let t1 = Date(timeIntervalSince1970: 2_000)   // distinct payload timestamp

    private static func seededState() -> SessionState {
        SessionState(sessions: [
            AgentSession(
                id: "s1",
                title: "T",
                tool: .claudeCode,
                phase: .running,
                summary: "s",
                updatedAt: t0
            )
        ])
    }

    // MARK: - A1: Codex

    @Test
    func codexArmSetsClearsAndStampsAndGuards() {
        // set
        var state = Self.seededState()
        state.apply(.sessionMetadataUpdated(.init(
            sessionID: "s1",
            codexMetadata: CodexSessionMetadata(initialUserPrompt: "hi"),
            timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.codexMetadata?.initialUserPrompt == "hi")
        #expect(state.session(id: "s1")?.updatedAt == Self.t1)

        // isEmpty → nil
        state.apply(.sessionMetadataUpdated(.init(
            sessionID: "s1", codexMetadata: CodexSessionMetadata(), timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.codexMetadata == nil)

        // unknown sessionID → no-op
        var untouched = Self.seededState()
        untouched.apply(.sessionMetadataUpdated(.init(
            sessionID: "missing", codexMetadata: CodexSessionMetadata(initialUserPrompt: "x"), timestamp: Self.t1
        )))
        #expect(untouched.session(id: "missing") == nil)
        #expect(untouched.session(id: "s1")?.updatedAt == Self.t0)   // existing unchanged
    }

    // MARK: - A2: Claude

    @Test
    func claudeArmSetsClearsAndStampsAndGuards() {
        var state = Self.seededState()
        state.apply(.claudeSessionMetadataUpdated(.init(
            sessionID: "s1",
            claudeMetadata: ClaudeSessionMetadata(initialUserPrompt: "hi"),
            timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.claudeMetadata?.initialUserPrompt == "hi")
        #expect(state.session(id: "s1")?.updatedAt == Self.t1)

        state.apply(.claudeSessionMetadataUpdated(.init(
            sessionID: "s1", claudeMetadata: ClaudeSessionMetadata(), timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.claudeMetadata == nil)

        var untouched = Self.seededState()
        untouched.apply(.claudeSessionMetadataUpdated(.init(
            sessionID: "missing", claudeMetadata: ClaudeSessionMetadata(initialUserPrompt: "x"), timestamp: Self.t1
        )))
        #expect(untouched.session(id: "missing") == nil)
        #expect(untouched.session(id: "s1")?.updatedAt == Self.t0)
    }

    // MARK: - A3: Gemini

    @Test
    func geminiArmSetsClearsAndStampsAndGuards() {
        var state = Self.seededState()
        state.apply(.geminiSessionMetadataUpdated(.init(
            sessionID: "s1",
            geminiMetadata: GeminiSessionMetadata(initialUserPrompt: "hi"),
            timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.geminiMetadata?.initialUserPrompt == "hi")
        #expect(state.session(id: "s1")?.updatedAt == Self.t1)

        state.apply(.geminiSessionMetadataUpdated(.init(
            sessionID: "s1", geminiMetadata: GeminiSessionMetadata(), timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.geminiMetadata == nil)

        var untouched = Self.seededState()
        untouched.apply(.geminiSessionMetadataUpdated(.init(
            sessionID: "missing", geminiMetadata: GeminiSessionMetadata(initialUserPrompt: "x"), timestamp: Self.t1
        )))
        #expect(untouched.session(id: "missing") == nil)
        #expect(untouched.session(id: "s1")?.updatedAt == Self.t0)
    }

    // MARK: - A4: OpenCode

    @Test
    func openCodeArmSetsClearsAndStampsAndGuards() {
        var state = Self.seededState()
        state.apply(.openCodeSessionMetadataUpdated(.init(
            sessionID: "s1",
            openCodeMetadata: OpenCodeSessionMetadata(initialUserPrompt: "hi"),
            timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.openCodeMetadata?.initialUserPrompt == "hi")
        #expect(state.session(id: "s1")?.updatedAt == Self.t1)

        state.apply(.openCodeSessionMetadataUpdated(.init(
            sessionID: "s1", openCodeMetadata: OpenCodeSessionMetadata(), timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.openCodeMetadata == nil)

        var untouched = Self.seededState()
        untouched.apply(.openCodeSessionMetadataUpdated(.init(
            sessionID: "missing", openCodeMetadata: OpenCodeSessionMetadata(initialUserPrompt: "x"), timestamp: Self.t1
        )))
        #expect(untouched.session(id: "missing") == nil)
        #expect(untouched.session(id: "s1")?.updatedAt == Self.t0)
    }

    // MARK: - A5: Cursor (direct arm test for uniform coverage of the future helper)

    @Test
    func cursorArmSetsClearsAndStampsAndGuards() {
        var state = Self.seededState()
        state.apply(.cursorSessionMetadataUpdated(.init(
            sessionID: "s1",
            cursorMetadata: CursorSessionMetadata(initialUserPrompt: "hi"),
            timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.cursorMetadata?.initialUserPrompt == "hi")
        #expect(state.session(id: "s1")?.updatedAt == Self.t1)

        state.apply(.cursorSessionMetadataUpdated(.init(
            sessionID: "s1", cursorMetadata: CursorSessionMetadata(), timestamp: Self.t1
        )))
        #expect(state.session(id: "s1")?.cursorMetadata == nil)

        var untouched = Self.seededState()
        untouched.apply(.cursorSessionMetadataUpdated(.init(
            sessionID: "missing", cursorMetadata: CursorSessionMetadata(initialUserPrompt: "x"), timestamp: Self.t1
        )))
        #expect(untouched.session(id: "missing") == nil)
        #expect(untouched.session(id: "s1")?.updatedAt == Self.t0)
    }
}
