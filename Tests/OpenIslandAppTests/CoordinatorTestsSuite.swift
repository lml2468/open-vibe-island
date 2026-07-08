import Testing
import Foundation
@testable import OpenIslandApp
import OpenIslandCore

/// Coverage for the two previously-untested coordinators (slice
/// `coordinator-tests`, discovery findings #4 + #16): the pure session-merge and
/// terminal-matching logic, plus the now-explicit unwired-`stateAccessor` signal.
@MainActor
struct CoordinatorTestsSuite {

    // MARK: - Helpers

    private func session(
        id: String,
        tool: AgentTool = .claudeCode,
        updatedAt: Date,
        attachmentState: SessionAttachmentState = .detached,
        jumpTarget: JumpTarget? = nil,
        claudeMetadata: ClaudeSessionMetadata? = nil,
        isCodexAppSession: Bool = false
    ) -> AgentSession {
        var s = AgentSession(
            id: id,
            title: "T-\(id)",
            tool: tool,
            origin: .live,
            attachmentState: attachmentState,
            phase: .running,
            summary: "s",
            updatedAt: updatedAt,
            jumpTarget: jumpTarget,
            claudeMetadata: claudeMetadata
        )
        s.isCodexAppSession = isCodexAppSession
        return s
    }

    // MARK: - A1/A2: unwired stateAccessor is observable, not silent

    @Test
    func discoveryCoordinatorCountsUnwiredStateAccessReads() {
        let c = SessionDiscoveryCoordinator()
        #expect(c.unwiredStateAccessReads == 0)
        // No stateAccessor wired → reading state (via a state-reading method)
        // must be observable, and still yield an empty result.
        let merged = c.mergeDiscoveredSessions([])
        #expect(merged.isEmpty)
        #expect(c.unwiredStateAccessReads >= 1)
    }

    @Test
    func monitoringCoordinatorCountsUnwiredStateAccessReads() {
        let c = ProcessMonitoringCoordinator()
        #expect(c.unwiredStateAccessReads == 0)
        _ = c.sessionIDsWithAliveProcesses(activeProcesses: [], isCodexAppRunning: false)
        #expect(c.unwiredStateAccessReads >= 1)
    }

    @Test
    func wiredStateAccessorNeverTripsCounterAndReturnsItsState() {
        let now = Date(timeIntervalSince1970: 1_000)
        let seeded = SessionState(sessions: [session(id: "a", updatedAt: now)])
        let c = SessionDiscoveryCoordinator()
        c.stateAccessor = { seeded }

        let merged = c.mergeDiscoveredSessions([])
        #expect(merged.map(\.id).sorted() == ["a"])
        #expect(c.unwiredStateAccessReads == 0)
    }

    // MARK: - A3: mergeDiscoveredSessions characterization

    @Test
    func mergeUpdatesExistingSessionByIDWithNewerFields() {
        let t0 = Date(timeIntervalSince1970: 2_000)
        let existing = session(id: "s1", updatedAt: t0, attachmentState: .attached, isCodexAppSession: true)
        let c = SessionDiscoveryCoordinator()
        c.stateAccessor = { SessionState(sessions: [existing]) }

        var discovered = session(id: "s1", updatedAt: t0.addingTimeInterval(10), attachmentState: .detached)
        discovered.summary = "newer"

        let merged = c.mergeDiscoveredSessions([discovered])
        #expect(merged.count == 1)
        let m = merged.first { $0.id == "s1" }
        #expect(m?.summary == "newer")                 // newer-wins field
        #expect(m?.updatedAt == t0.addingTimeInterval(10))
        #expect(m?.attachmentState == .attached)       // attached precedence preserved
        #expect(m?.isCodexAppSession == true)          // OR-ing preserves the flag
    }

    @Test
    func mergeKeepsExistingFieldsWhenDiscoveredIsOlder() {
        let t0 = Date(timeIntervalSince1970: 3_000)
        var existing = session(id: "s1", updatedAt: t0)
        existing.summary = "current"
        let c = SessionDiscoveryCoordinator()
        c.stateAccessor = { SessionState(sessions: [existing]) }

        var older = session(id: "s1", updatedAt: t0.addingTimeInterval(-10))
        older.summary = "stale"

        let merged = c.mergeDiscoveredSessions([older])
        #expect(merged.first { $0.id == "s1" }?.summary == "current")
    }

    @Test
    func mergeMatchesExistingByTranscriptPathWhenIDsDiffer() {
        let t0 = Date(timeIntervalSince1970: 4_000)
        let existing = session(
            id: "existing-id",
            updatedAt: t0,
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: "/tmp/x.jsonl")
        )
        let c = SessionDiscoveryCoordinator()
        c.stateAccessor = { SessionState(sessions: [existing]) }

        let discovered = session(
            id: "different-id",
            updatedAt: t0.addingTimeInterval(5),
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: "/tmp/x.jsonl")
        )

        let merged = c.mergeDiscoveredSessions([discovered])
        // Matched by transcript path → merged into the existing id, not inserted.
        #expect(merged.count == 1)
        #expect(merged.first?.id == "existing-id")
    }

    @Test
    func mergeInsertsGenuinelyNewSession() {
        let t0 = Date(timeIntervalSince1970: 5_000)
        let existing = session(id: "s1", updatedAt: t0)
        let c = SessionDiscoveryCoordinator()
        c.stateAccessor = { SessionState(sessions: [existing]) }

        let discovered = session(id: "s2", updatedAt: t0)
        let merged = c.mergeDiscoveredSessions([discovered])
        #expect(merged.map(\.id).sorted() == ["s1", "s2"])
    }

    // MARK: - A4: attachment-state precedence (via mergeDiscoveredSessions)

    @Test
    func attachmentStatePrecedenceAttachedBeatsStaleBeatsDetached() {
        let t0 = Date(timeIntervalSince1970: 6_000)
        func mergedAttachment(existing: SessionAttachmentState, discovered: SessionAttachmentState) -> SessionAttachmentState? {
            let c = SessionDiscoveryCoordinator()
            c.stateAccessor = { SessionState(sessions: [session(id: "s1", updatedAt: t0, attachmentState: existing)]) }
            let d = session(id: "s1", updatedAt: t0, attachmentState: discovered)
            return c.mergeDiscoveredSessions([d]).first { $0.id == "s1" }?.attachmentState
        }

        #expect(mergedAttachment(existing: .detached, discovered: .attached) == .attached)
        #expect(mergedAttachment(existing: .attached, discovered: .detached) == .attached)
        #expect(mergedAttachment(existing: .detached, discovered: .stale) == .stale)
        #expect(mergedAttachment(existing: .stale, discovered: .detached) == .stale)
        #expect(mergedAttachment(existing: .detached, discovered: .detached) == .detached)
    }

    // MARK: - A5: ProcessMonitoringCoordinator pure helpers

    @Test
    func supportedTerminalAppMapsAliasesAndRejectsUnknown() {
        let c = ProcessMonitoringCoordinator()
        #expect(c.supportedTerminalApp(for: "ghostty") == "Ghostty")
        #expect(c.supportedTerminalApp(for: "  iTerm2  ") == "iTerm")
        #expect(c.supportedTerminalApp(for: "apple_terminal") == "Terminal")
        #expect(c.supportedTerminalApp(for: "code") == "VS Code")
        #expect(c.supportedTerminalApp(for: "idea") == "IntelliJ IDEA")
        #expect(c.supportedTerminalApp(for: "totally-unknown") == nil)
        #expect(c.supportedTerminalApp(for: "") == nil)
        #expect(c.supportedTerminalApp(for: nil) == nil)
    }

    @Test
    func normalizedTTYAndPathHelpers() {
        let c = ProcessMonitoringCoordinator()
        #expect(c.normalizedTTYForMatching("ttys002") == "/dev/ttys002")
        #expect(c.normalizedTTYForMatching("/dev/ttys003") == "/dev/ttys003")
        #expect(c.normalizedTTYForMatching("  ") == nil)
        #expect(c.normalizedTTYForMatching(nil) == nil)
        #expect(c.normalizedPathForMatching("  ") == nil)
        #expect(c.normalizedPathForMatching(nil) == nil)
        // Standardized + lowercased.
        #expect(c.normalizedPathForMatching("/tmp/Foo/../Bar") == "/tmp/bar")
    }

    @Test
    func liveAttachmentKeyBranches() {
        let c = ProcessMonitoringCoordinator()

        // nil when there's no jumpTarget.
        #expect(c.liveAttachmentKey(for: session(id: "n", updatedAt: .init(timeIntervalSince1970: 1))) == nil)

        // Codex.app thread branch.
        let codex = session(
            id: "cx", updatedAt: .init(timeIntervalSince1970: 1),
            jumpTarget: JumpTarget(terminalApp: "Codex.app", workspaceName: "w", paneTitle: "p", codexThreadID: "THREAD-9"),
            isCodexAppSession: true
        )
        #expect(c.liveAttachmentKey(for: codex) == "codex.app:thread:thread-9")

        // terminalSessionID branch.
        let sess = session(
            id: "id", updatedAt: .init(timeIntervalSince1970: 1),
            jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: "w", paneTitle: "p", terminalSessionID: "ABC")
        )
        #expect(c.liveAttachmentKey(for: sess) == "ghostty:session:abc")

        // TTY branch.
        let tty = session(
            id: "id2", updatedAt: .init(timeIntervalSince1970: 1),
            jumpTarget: JumpTarget(terminalApp: "iTerm", workspaceName: "w", paneTitle: "p", terminalTTY: "ttys004")
        )
        #expect(c.liveAttachmentKey(for: tty) == "iterm:tty:/dev/ttys004")
    }
}
