import Foundation
import Testing
@testable import OpenIslandCore

/// Direct unit coverage for the pure per-agent metadata/tool/preview mergers
/// (slice `bridge-metadata-merging`, discovery finding #3). Before this extraction
/// only the Claude path was exercised indirectly via the bridge; these pin the
/// per-agent clear/keep-on-lifecycle rules and the field-merge precedence directly.
struct BridgeMetadataMergingTests {

    // MARK: - A1: metadata field-merge precedence (update ?? existing + fallbacks)

    @Test
    func codexMetadataMergesFieldsUpdateWinsElseExisting() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/old.jsonl",
            initialUserPrompt: "first",
            lastUserPrompt: "old-last",
            lastAssistantMessage: "old-assistant"
        )
        let update = CodexSessionMetadata(
            lastUserPrompt: "new-last",
            lastAssistantMessage: "new-assistant"
        )
        let merged = BridgeMetadataMerging.mergedCodexMetadata(
            existing: existing, update: update, hookEventName: .userPromptSubmit
        )
        #expect(merged.transcriptPath == "/old.jsonl")          // update nil → existing
        #expect(merged.initialUserPrompt == "first")            // existing ?? update ?? update.lastUserPrompt
        #expect(merged.lastUserPrompt == "new-last")            // update wins
        #expect(merged.lastAssistantMessage == "new-assistant") // update wins
    }

    @Test
    func metadataInitialUserPromptFallsBackToUpdateLastUserPrompt() {
        // existing nil initialUserPrompt, update nil initialUserPrompt → update.lastUserPrompt
        let update = OpenCodeSessionMetadata(lastUserPrompt: "the-first-thing")
        let merged = BridgeMetadataMerging.mergedOpenCodeMetadata(
            existing: nil, update: update, hookEventName: .userPromptSubmit
        )
        #expect(merged.initialUserPrompt == "the-first-thing")
    }

    // MARK: - A2: tool/preview clear-on-lifecycle, per agent

    @Test
    func codexToolUpdateWinsThenClearsOnLifecycleElseKeeps() {
        // update present → wins
        #expect(BridgeMetadataMerging.mergedCodexCurrentTool(
            existing: "old", update: "new", hookEventName: .preToolUse) == "new")
        // update nil + clearing event → nil
        #expect(BridgeMetadataMerging.mergedCodexCurrentTool(
            existing: "old", update: nil, hookEventName: .postToolUse) == nil)
        #expect(BridgeMetadataMerging.mergedCodexCurrentTool(
            existing: "old", update: nil, hookEventName: .stop) == nil)
        // update nil + non-clearing event → keep existing
        #expect(BridgeMetadataMerging.mergedCodexCurrentTool(
            existing: "old", update: nil, hookEventName: .preToolUse) == "old")
    }

    @Test
    func openCodeToolClearsOnLifecycleElseKeeps() {
        #expect(BridgeMetadataMerging.mergedOpenCodeCurrentTool(
            existing: "old", update: nil, hookEventName: .postToolUse) == nil)
        #expect(BridgeMetadataMerging.mergedOpenCodeCurrentTool(
            existing: "old", update: nil, hookEventName: .stop) == nil)
        #expect(BridgeMetadataMerging.mergedOpenCodeCurrentTool(
            existing: "old", update: nil, hookEventName: .preToolUse) == "old")
        #expect(BridgeMetadataMerging.mergedOpenCodeCurrentToolInputPreview(
            existing: "prev", update: nil, hookEventName: .sessionEnd) == nil)
        #expect(BridgeMetadataMerging.mergedOpenCodeCurrentToolInputPreview(
            existing: "prev", update: nil, hookEventName: .sessionStart) == "prev")
    }

    @Test
    func claudeToolClearsOnLifecycleElseKeeps() {
        #expect(BridgeMetadataMerging.mergedClaudeCurrentTool(
            existing: "old", update: nil, hookEventName: .postToolUse) == nil)
        #expect(BridgeMetadataMerging.mergedClaudeCurrentTool(
            existing: "old", update: nil, hookEventName: .stop) == nil)
        #expect(BridgeMetadataMerging.mergedClaudeCurrentTool(
            existing: "old", update: nil, hookEventName: .preToolUse) == "old")
        #expect(BridgeMetadataMerging.mergedClaudeCurrentToolInputPreview(
            existing: "prev", update: nil, hookEventName: .sessionEnd) == nil)
        #expect(BridgeMetadataMerging.mergedClaudeCurrentToolInputPreview(
            existing: "prev", update: nil, hookEventName: .notification) == "prev")
    }

    @Test
    func codexCommandPreviewClearsOnLifecycleElseKeeps() {
        #expect(BridgeMetadataMerging.mergedCodexCurrentCommandPreview(
            existing: "cmd", update: nil, hookEventName: .stop) == nil)
        #expect(BridgeMetadataMerging.mergedCodexCurrentCommandPreview(
            existing: "cmd", update: "newcmd", hookEventName: .stop) == "newcmd")
        #expect(BridgeMetadataMerging.mergedCodexCurrentCommandPreview(
            existing: "cmd", update: nil, hookEventName: .preToolUse) == "cmd")
    }

    // MARK: - A3: Claude subagent-lifecycle holds agentID/agentType

    @Test
    func claudeSubagentLifecycleHoldsAgentIdentityAndPreservesTasks() {
        let existing = ClaudeSessionMetadata(
            agentID: "existing-agent",
            agentType: "existing-type",
            activeSubagents: [],
            activeTasks: []
        )
        let update = ClaudeSessionMetadata(agentID: "update-agent", agentType: "update-type")

        // subagentStop is a subagent-lifecycle event → hold existing identity
        let held = BridgeMetadataMerging.mergedClaudeMetadata(
            existing: existing, update: update, hookEventName: .subagentStop
        )
        #expect(held.agentID == "existing-agent")
        #expect(held.agentType == "existing-type")

        // a non-lifecycle event → update wins
        let taken = BridgeMetadataMerging.mergedClaudeMetadata(
            existing: existing, update: update, hookEventName: .preToolUse
        )
        #expect(taken.agentID == "update-agent")
        #expect(taken.agentType == "update-type")
    }
}
