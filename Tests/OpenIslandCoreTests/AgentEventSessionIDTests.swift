import Foundation
import Testing
@testable import OpenIslandCore

/// Characterizes `AgentEvent.sessionID` — the computed property that replaces the
/// two 12-case re-enumerations in AppModel / ProcessMonitoringCoordinator (slice
/// `agentevent-sessionid`, discovery finding #10). Every case must expose the
/// sessionID its payload was constructed with.
struct AgentEventSessionIDTests {
    private static let ts = Date(timeIntervalSince1970: 1_700_000_000)

    /// One event per enum case, each tagged with a distinct sessionID so a
    /// mis-wired arm (returning the wrong payload's id, or a constant) is caught.
    private static var casesWithExpectedID: [(event: AgentEvent, id: String)] {
        [
            (.sessionStarted(.init(sessionID: "id-started", title: "t", tool: .claudeCode, initialPhase: .running, summary: "s", timestamp: ts)), "id-started"),
            (.activityUpdated(.init(sessionID: "id-activity", summary: "s", phase: .running, timestamp: ts)), "id-activity"),
            (.permissionRequested(.init(sessionID: "id-perm", request: PermissionRequest(title: "t", summary: "s", affectedPath: "/tmp/x"), timestamp: ts)), "id-perm"),
            (.questionAsked(.init(sessionID: "id-question", prompt: QuestionPrompt(title: "q", options: ["a", "b"]), timestamp: ts)), "id-question"),
            (.sessionCompleted(.init(sessionID: "id-completed", summary: "done", timestamp: ts)), "id-completed"),
            (.jumpTargetUpdated(.init(sessionID: "id-jump", jumpTarget: JumpTarget(terminalApp: "Terminal", workspaceName: "w", paneTitle: "p"), timestamp: ts)), "id-jump"),
            (.sessionMetadataUpdated(.init(sessionID: "id-codex", codexMetadata: CodexSessionMetadata(initialUserPrompt: "hi"), timestamp: ts)), "id-codex"),
            (.claudeSessionMetadataUpdated(.init(sessionID: "id-claude", claudeMetadata: ClaudeSessionMetadata(), timestamp: ts)), "id-claude"),
            (.geminiSessionMetadataUpdated(.init(sessionID: "id-gemini", geminiMetadata: GeminiSessionMetadata(), timestamp: ts)), "id-gemini"),
            (.openCodeSessionMetadataUpdated(.init(sessionID: "id-opencode", openCodeMetadata: OpenCodeSessionMetadata(), timestamp: ts)), "id-opencode"),
            (.cursorSessionMetadataUpdated(.init(sessionID: "id-cursor", cursorMetadata: CursorSessionMetadata(), timestamp: ts)), "id-cursor"),
            (.actionableStateResolved(.init(sessionID: "id-actionable", summary: "ok", timestamp: ts)), "id-actionable"),
        ]
    }

    @Test
    func sessionIDReturnsWrappedPayloadIDForEveryCase() {
        for entry in Self.casesWithExpectedID {
            #expect(entry.event.sessionID == entry.id)
        }
    }
}
