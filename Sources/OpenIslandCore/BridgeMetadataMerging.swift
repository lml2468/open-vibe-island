import Foundation

/// Pure metadata/tool/preview merge helpers for the per-agent bridge hook
/// handlers, extracted from `BridgeServer` (slice `bridge-metadata-merging`,
/// discovery finding #3). These are referentially transparent — they take the
/// existing metadata, the incoming update, and the hook event, and return the
/// merged value with no access to server state — so they live in a standalone,
/// directly-testable namespace rather than as private methods on the server.
enum BridgeMetadataMerging {
    // RED STUBS — return wrong values so the failing-first tests compile and fail
    // on assertion. Replaced in Green with the verbatim bodies from BridgeServer.

    static func mergedOpenCodeMetadata(
        existing: OpenCodeSessionMetadata?,
        update: OpenCodeSessionMetadata,
        hookEventName: OpenCodeHookEventName
    ) -> OpenCodeSessionMetadata {
        OpenCodeSessionMetadata()
    }

    static func mergedOpenCodeCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: OpenCodeHookEventName
    ) -> String? {
        nil
    }

    static func mergedOpenCodeCurrentToolInputPreview(
        existing: String?,
        update: String?,
        hookEventName: OpenCodeHookEventName
    ) -> String? {
        nil
    }

    static func mergedCodexMetadata(
        existing: CodexSessionMetadata?,
        update: CodexSessionMetadata,
        hookEventName: CodexHookEventName
    ) -> CodexSessionMetadata {
        CodexSessionMetadata()
    }

    static func mergedCodexCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: CodexHookEventName
    ) -> String? {
        nil
    }

    static func mergedCodexCurrentCommandPreview(
        existing: String?,
        update: String?,
        hookEventName: CodexHookEventName
    ) -> String? {
        nil
    }

    static func mergedClaudeMetadata(
        existing: ClaudeSessionMetadata?,
        update: ClaudeSessionMetadata,
        hookEventName: ClaudeHookEventName
    ) -> ClaudeSessionMetadata {
        ClaudeSessionMetadata()
    }

    static func mergedClaudeCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: ClaudeHookEventName
    ) -> String? {
        nil
    }

    static func mergedClaudeCurrentToolInputPreview(
        existing: String?,
        update: String?,
        hookEventName: ClaudeHookEventName
    ) -> String? {
        nil
    }
}
