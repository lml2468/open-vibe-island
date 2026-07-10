import Foundation

/// Pure metadata/tool/preview merge helpers for the per-agent bridge hook
/// handlers, extracted from `BridgeServer` (slice `bridge-metadata-merging`,
/// discovery finding #3). These are referentially transparent — they take the
/// existing metadata, the incoming update, and the hook event, and return the
/// merged value with no access to server state — so they live in a standalone,
/// directly-testable namespace rather than as private methods on the server.
enum BridgeMetadataMerging {

    // MARK: - OpenCode

    static func mergedOpenCodeMetadata(
        existing: OpenCodeSessionMetadata?,
        update: OpenCodeSessionMetadata,
        hookEventName: OpenCodeHookEventName
    ) -> OpenCodeSessionMetadata {
        OpenCodeSessionMetadata(
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedOpenCodeCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentToolInputPreview: mergedOpenCodeCurrentToolInputPreview(
                existing: existing?.currentToolInputPreview,
                update: update.currentToolInputPreview,
                hookEventName: hookEventName
            ),
            model: update.model ?? existing?.model
        )
    }

    static func mergedOpenCodeCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: OpenCodeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .stop, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .questionAsked:
            return existing
        }
    }

    static func mergedOpenCodeCurrentToolInputPreview(
        existing: String?,
        update: String?,
        hookEventName: OpenCodeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .stop, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .questionAsked:
            return existing
        }
    }

    // MARK: - Codex

    static func mergedCodexMetadata(
        existing: CodexSessionMetadata?,
        update: CodexSessionMetadata,
        hookEventName: CodexHookEventName
    ) -> CodexSessionMetadata {
        CodexSessionMetadata(
            transcriptPath: update.transcriptPath ?? existing?.transcriptPath,
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedCodexCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentCommandPreview: mergedCodexCurrentCommandPreview(
                existing: existing?.currentCommandPreview,
                update: update.currentCommandPreview,
                hookEventName: hookEventName
            )
        )
    }

    static func mergedCodexCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: CodexHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .userPromptSubmit, .postToolUse, .stop:
            return nil
        case .sessionStart, .preToolUse, .permissionRequest:
            return existing
        }
    }

    static func mergedCodexCurrentCommandPreview(
        existing: String?,
        update: String?,
        hookEventName: CodexHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .userPromptSubmit, .postToolUse, .stop:
            return nil
        case .sessionStart, .preToolUse, .permissionRequest:
            return existing
        }
    }

    // MARK: - Claude

    static func mergedClaudeMetadata(
        existing: ClaudeSessionMetadata?,
        update: ClaudeSessionMetadata,
        hookEventName: ClaudeHookEventName
    ) -> ClaudeSessionMetadata {
        ClaudeSessionMetadata(
            transcriptPath: update.transcriptPath ?? existing?.transcriptPath,
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedClaudeCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentToolInputPreview: mergedClaudeCurrentToolInputPreview(
                existing: existing?.currentToolInputPreview,
                update: update.currentToolInputPreview,
                hookEventName: hookEventName
            ),
            model: update.model ?? existing?.model,
            startupSource: update.startupSource ?? existing?.startupSource,
            permissionMode: update.permissionMode ?? existing?.permissionMode,
            agentID: hookEventName.isSubagentLifecycle
                ? existing?.agentID
                : update.agentID ?? existing?.agentID,
            agentType: hookEventName.isSubagentLifecycle
                ? existing?.agentType
                : update.agentType ?? existing?.agentType,
            worktreeBranch: update.worktreeBranch ?? existing?.worktreeBranch,
            activeSubagents: existing?.activeSubagents ?? [],
            activeTasks: existing?.activeTasks ?? []
        )
    }

    static func mergedClaudeCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: ClaudeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .postToolUseFailure, .permissionDenied, .stop, .stopFailure, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .notification, .subagentStart, .subagentStop, .preCompact:
            return existing
        }
    }

    static func mergedClaudeCurrentToolInputPreview(
        existing: String?,
        update: String?,
        hookEventName: ClaudeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .postToolUseFailure, .permissionDenied, .stop, .stopFailure, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .notification, .subagentStart, .subagentStop, .preCompact:
            return existing
        }
    }
}
