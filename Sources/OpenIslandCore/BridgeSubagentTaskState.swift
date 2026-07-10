import Foundation

/// Pure Claude subagent-lifecycle transforms over `ClaudeSessionMetadata`, extracted
/// from `BridgeServer` (slice `bridge-subagent-state`, discovery finding #3). Each
/// returns the new metadata, or `nil` when nothing changed (so the BridgeServer
/// wrapper can skip the emit) — mirroring the server's existing no-op emit guards.
/// No server state / queue / socket access: the fetch + emit orchestration stays in
/// the wrapper.
enum BridgeSubagentState {
    // RED STUBS — replaced in Green.
    static func adding(_ subagent: ClaudeSubagentInfo, to metadata: ClaudeSessionMetadata) -> ClaudeSessionMetadata {
        metadata
    }

    static func removing(agentID: String, from metadata: ClaudeSessionMetadata) -> ClaudeSessionMetadata? {
        nil
    }

    static func clearingAll(from metadata: ClaudeSessionMetadata) -> ClaudeSessionMetadata? {
        nil
    }

    static func removingStale(
        from metadata: ClaudeSessionMetadata,
        now: Date,
        timeout: TimeInterval
    ) -> ClaudeSessionMetadata? {
        nil
    }
}

/// Pure Claude task-tracking transforms over `ClaudeSessionMetadata`, extracted from
/// `BridgeServer`. Same contract as `BridgeSubagentState`: `nil` = no change.
/// `parseRealTaskID` is the pure parser for the TaskCreate tool response.
enum BridgeTaskState {
    // RED STUBS — replaced in Green.
    static func creating(
        title: String,
        id: String,
        status: ClaudeTaskInfo.Status,
        in metadata: ClaudeSessionMetadata
    ) -> ClaudeSessionMetadata {
        metadata
    }

    static func updatingStatus(
        taskID: String,
        status: ClaudeTaskInfo.Status?,
        in metadata: ClaudeSessionMetadata
    ) -> ClaudeSessionMetadata {
        metadata
    }

    static func replacingID(
        tempID: String,
        realID: String,
        in metadata: ClaudeSessionMetadata
    ) -> ClaudeSessionMetadata? {
        nil
    }

    static func parseRealTaskID(from response: ClaudeHookJSONValue?) -> String? {
        nil
    }
}
