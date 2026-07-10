import Foundation

/// Pure Claude subagent-lifecycle transforms over `ClaudeSessionMetadata`, extracted
/// from `BridgeServer` (slice `bridge-subagent-state`, discovery finding #3). Each
/// returns the new metadata, or `nil` when nothing changed (so the BridgeServer
/// wrapper can skip the emit) — mirroring the server's existing no-op emit guards.
/// No server state / queue / socket access: the fetch + emit orchestration stays in
/// the wrapper.
enum BridgeSubagentState {
    static func adding(_ subagent: ClaudeSubagentInfo, to metadata: ClaudeSessionMetadata) -> ClaudeSessionMetadata {
        var metadata = metadata
        metadata.activeSubagents.removeAll { $0.agentID == subagent.agentID }
        metadata.activeSubagents.append(subagent)
        return metadata
    }

    static func removing(agentID: String, from metadata: ClaudeSessionMetadata) -> ClaudeSessionMetadata? {
        var metadata = metadata
        let previousCount = metadata.activeSubagents.count
        metadata.activeSubagents.removeAll { $0.agentID == agentID }
        guard metadata.activeSubagents.count != previousCount else {
            return nil
        }
        return metadata
    }

    static func clearingAll(from metadata: ClaudeSessionMetadata) -> ClaudeSessionMetadata? {
        guard !metadata.activeSubagents.isEmpty else {
            return nil
        }
        var metadata = metadata
        metadata.activeSubagents.removeAll()
        return metadata
    }

    static func removingStale(
        from metadata: ClaudeSessionMetadata,
        now: Date,
        timeout: TimeInterval
    ) -> ClaudeSessionMetadata? {
        guard !metadata.activeSubagents.isEmpty else {
            return nil
        }
        var metadata = metadata
        let before = metadata.activeSubagents.count
        metadata.activeSubagents.removeAll { sub in
            guard let started = sub.startedAt else { return false }
            return now.timeIntervalSince(started) > timeout
        }
        guard metadata.activeSubagents.count != before else { return nil }
        return metadata
    }
}

/// Pure Claude task-tracking transforms over `ClaudeSessionMetadata`, extracted from
/// `BridgeServer`. Same contract as `BridgeSubagentState`: `nil` = no change.
/// `parseRealTaskID` is the pure parser for the TaskCreate tool response.
enum BridgeTaskState {
    static func creating(
        title: String,
        id: String,
        status: ClaudeTaskInfo.Status,
        in metadata: ClaudeSessionMetadata
    ) -> ClaudeSessionMetadata {
        var metadata = metadata
        metadata.activeTasks.append(ClaudeTaskInfo(id: id, title: title, status: status))
        return metadata
    }

    static func updatingStatus(
        taskID: String,
        status: ClaudeTaskInfo.Status?,
        in metadata: ClaudeSessionMetadata
    ) -> ClaudeSessionMetadata {
        var metadata = metadata
        if let idx = metadata.activeTasks.firstIndex(where: { $0.id == taskID }), let status {
            metadata.activeTasks[idx].status = status
        }
        return metadata
    }

    static func replacingID(
        tempID: String,
        realID: String,
        in metadata: ClaudeSessionMetadata
    ) -> ClaudeSessionMetadata? {
        guard let idx = metadata.activeTasks.firstIndex(where: { $0.id == tempID }) else {
            return nil
        }
        var metadata = metadata
        metadata.activeTasks[idx].id = realID
        return metadata
    }

    /// Extract the real task ID from a TaskCreate tool response. Mirrors the shapes
    /// Claude Code emits: nested `{"task": {"id": "7"}}` (string or number), top-level
    /// `taskId`/`task_id`/`id`, or a string like `"Task #7 created successfully"`.
    static func parseRealTaskID(from response: ClaudeHookJSONValue?) -> String? {
        switch response {
        case let .object(obj):
            // Primary: nested under "task" object — {"task": {"id": "7"}}
            if case let .object(taskObj) = obj["task"],
               let idVal = taskObj["id"] ?? taskObj["taskId"] {
                if case let .string(s) = idVal { return s }
                if case let .number(n) = idVal { return String(Int(n)) }
            }
            // Fallback: top-level "taskId", "task_id", "id"
            return (obj["taskId"] ?? obj["task_id"] ?? obj["id"]).flatMap {
                if case let .string(s) = $0 { s } else { nil }
            }
        case let .string(s):
            // Fallback for string responses like "Task #7 created successfully"
            if let idRange = s.range(of: #"(?<=Task #)\S+"#, options: .regularExpression) {
                return String(s[idRange])
            }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }
}
