import Foundation
import Testing
@testable import OpenIslandCore

/// Direct unit coverage for the pure Claude subagent/task state transforms extracted
/// from BridgeServer (slice `bridge-subagent-state`, discovery finding #3). Before
/// this the array logic + the TaskCreate-response parser had no direct tests (only
/// merge-preservation + incidental subagentStop end-to-end).
struct BridgeSubagentTaskStateTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private func subagent(_ id: String, startedAt: Date? = nil) -> ClaudeSubagentInfo {
        ClaudeSubagentInfo(agentID: id, agentType: "t", summary: nil, taskDescription: nil, startedAt: startedAt)
    }

    private func metadata(
        subagents: [ClaudeSubagentInfo] = [],
        tasks: [ClaudeTaskInfo] = []
    ) -> ClaudeSessionMetadata {
        var m = ClaudeSessionMetadata()
        m.activeSubagents = subagents
        m.activeTasks = tasks
        return m
    }

    // MARK: - A1: subagent add / remove / clear

    @Test
    func addingDedupsByAgentIDThenAppends() {
        let m = metadata(subagents: [subagent("a"), subagent("b")])
        let result = BridgeSubagentState.adding(subagent("a", startedAt: Self.now), to: m)
        // "a" removed then re-appended → order becomes b, a; count stays 2.
        #expect(result.activeSubagents.map(\.agentID) == ["b", "a"])
        #expect(result.activeSubagents.last?.startedAt == Self.now)
    }

    @Test
    func removingReturnsNilWhenAgentAbsentElseTrims() {
        let m = metadata(subagents: [subagent("a"), subagent("b")])
        #expect(BridgeSubagentState.removing(agentID: "missing", from: m) == nil)
        let result = BridgeSubagentState.removing(agentID: "a", from: m)
        #expect(result?.activeSubagents.map(\.agentID) == ["b"])
    }

    @Test
    func clearingAllReturnsNilWhenEmptyElseEmpties() {
        #expect(BridgeSubagentState.clearingAll(from: metadata()) == nil)
        let result = BridgeSubagentState.clearingAll(from: metadata(subagents: [subagent("a")]))
        #expect(result?.activeSubagents.isEmpty == true)
    }

    // MARK: - A2: stale removal with injected now

    @Test
    func removingStaleRespectsTimeoutBoundaryAndNilStartedAt() {
        let timeout: TimeInterval = 180
        let fresh = subagent("fresh", startedAt: Self.now.addingTimeInterval(-179))   // just under → kept
        let stale = subagent("stale", startedAt: Self.now.addingTimeInterval(-181))   // just over → removed
        let noStart = subagent("nostart", startedAt: nil)                             // never stale

        let result = BridgeSubagentState.removingStale(
            from: metadata(subagents: [fresh, stale, noStart]),
            now: Self.now,
            timeout: timeout
        )
        #expect(result?.activeSubagents.map(\.agentID) == ["fresh", "nostart"])

        // Nothing removed → nil.
        #expect(BridgeSubagentState.removingStale(
            from: metadata(subagents: [fresh, noStart]), now: Self.now, timeout: timeout
        ) == nil)
    }

    // MARK: - A3: task create / update

    @Test
    func creatingAppendsTask() {
        let result = BridgeTaskState.creating(
            title: "Do it", id: "temp-1", status: .pending, in: metadata()
        )
        #expect(result.activeTasks.map(\.id) == ["temp-1"])
        #expect(result.activeTasks.first?.title == "Do it")
        #expect(result.activeTasks.first?.status == .pending)
    }

    @Test
    func updatingStatusSetsMatchingTaskElseLeavesUnchanged() {
        let m = metadata(tasks: [ClaudeTaskInfo(id: "t1", title: "T", status: .pending)])
        let updated = BridgeTaskState.updatingStatus(taskID: "t1", status: .completed, in: m)
        #expect(updated.activeTasks.first?.status == .completed)

        // Unknown taskID → unchanged (wrapper still emits; this func returns metadata as-is).
        let noMatch = BridgeTaskState.updatingStatus(taskID: "nope", status: .completed, in: m)
        #expect(noMatch.activeTasks.first?.status == .pending)

        // Nil status → unchanged.
        let nilStatus = BridgeTaskState.updatingStatus(taskID: "t1", status: nil, in: m)
        #expect(nilStatus.activeTasks.first?.status == .pending)
    }

    // MARK: - A4: replaceTaskID + parseRealTaskID (the 3 response shapes)

    @Test
    func replacingIDReturnsNilWhenTempAbsentElseSetsRealID() {
        let m = metadata(tasks: [ClaudeTaskInfo(id: "temp", title: "T", status: .pending)])
        #expect(BridgeTaskState.replacingID(tempID: "missing", realID: "7", in: m) == nil)
        let result = BridgeTaskState.replacingID(tempID: "temp", realID: "7", in: m)
        #expect(result?.activeTasks.first?.id == "7")
    }

    @Test
    func parseRealTaskIDFromNestedTaskObjectStringAndNumber() {
        let strShape = ClaudeHookJSONValue.object(["task": .object(["id": .string("7")])])
        #expect(BridgeTaskState.parseRealTaskID(from: strShape) == "7")

        let numShape = ClaudeHookJSONValue.object(["task": .object(["taskId": .number(7)])])
        #expect(BridgeTaskState.parseRealTaskID(from: numShape) == "7")
    }

    @Test
    func parseRealTaskIDFromTopLevelKeys() {
        #expect(BridgeTaskState.parseRealTaskID(from: .object(["taskId": .string("9")])) == "9")
        #expect(BridgeTaskState.parseRealTaskID(from: .object(["task_id": .string("9")])) == "9")
        #expect(BridgeTaskState.parseRealTaskID(from: .object(["id": .string("9")])) == "9")
    }

    @Test
    func parseRealTaskIDFromStringRegexAndTrimmedAndEmpty() {
        #expect(BridgeTaskState.parseRealTaskID(from: .string("Task #42 created successfully")) == "42")
        #expect(BridgeTaskState.parseRealTaskID(from: .string("  bare-id  ")) == "bare-id")
        #expect(BridgeTaskState.parseRealTaskID(from: .string("   ")) == nil)
        #expect(BridgeTaskState.parseRealTaskID(from: nil) == nil)
        #expect(BridgeTaskState.parseRealTaskID(from: .null) == nil)
    }
}
