import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Direct unit coverage for the pure sectioning derivation extracted from AppModel
/// (slice `sectioning-extract`, discovery finding #8). Complements the through-
/// AppModel characterization (SessionSectioningTests) with direct presenter tests,
/// notably the now-parameterized state split.
struct SessionListPresenterSectioningTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let stale: TimeInterval = 300

    private func session(
        id: String,
        tool: AgentTool = .codex,
        phase: SessionPhase = .running,
        updatedAt: Date = SessionListPresenterSectioningTests.now,
        workspaceName: String? = nil,
        title: String? = nil,
        includeJumpTarget: Bool = true
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: title ?? "T-\(id)",
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "s",
            updatedAt: updatedAt,
            jumpTarget: includeJumpTarget
                ? JumpTarget(terminalApp: "Ghostty", workspaceName: workspaceName ?? id, paneTitle: "p-\(id)")
                : nil
        )
    }

    // MARK: - A1: sortSessions modes

    @Test
    func sortSessionsAttentionIsIdentityLastUpdateSortsByActivityDesc() {
        let older = session(id: "older", updatedAt: Self.now.addingTimeInterval(-100))
        let newer = session(id: "newer", updatedAt: Self.now)
        let input = [older, newer]

        #expect(SessionListPresenter.sortSessions(input, by: .attention).map(\.id) == ["older", "newer"])
        #expect(SessionListPresenter.sortSessions(input, by: .lastUpdate).map(\.id) == ["newer", "older"])
    }

    // MARK: - A2: stateGroupedSections split with injected now

    @Test
    func stateGroupedSectionsSplitsDoneVsIdleByInjectedNow() {
        var approval = session(id: "ap", phase: .waitingForApproval)
        approval.permissionRequest = PermissionRequest(title: "a", summary: "s", affectedPath: "/tmp")
        let done = session(id: "done", phase: .completed, updatedAt: Self.now.addingTimeInterval(-60))    // fresh (< 300)
        let idle = session(id: "idle", phase: .completed, updatedAt: Self.now.addingTimeInterval(-600))   // stale (> 300)

        let sections = SessionListPresenter.stateGroupedSections(
            from: [approval, done, idle],
            staleThresholdSeconds: Self.stale,
            now: Self.now
        )
        #expect(sections.map(\.id) == ["state-approval", "state-done", "state-idle"])
        #expect(sections.first { $0.id == "state-done" }?.sessions.map(\.id) == ["done"])
        #expect(sections.first { $0.id == "state-idle" }?.sessions.map(\.id) == ["idle"])
    }

    // MARK: - A3: sections grouping dispatch + projectGroupName

    @Test
    func sectionsNoneYieldsSingleAllSection() {
        let s = session(id: "x")
        let sections = SessionListPresenter.sections(
            from: [s], group: .none, sort: .attention, staleThresholdSeconds: Self.stale, now: Self.now
        )
        #expect(sections.map(\.id) == ["all"])
        #expect(sections.first?.title == "island.section.sessions")
    }

    @Test
    func sectionsAgentGroupsPerToolInAllCasesOrder() {
        let codex = session(id: "cx", tool: .codex)
        let claude = session(id: "cl", tool: .claudeCode)
        let sections = SessionListPresenter.sections(
            from: [codex, claude], group: .agent, sort: .attention, staleThresholdSeconds: Self.stale, now: Self.now
        )
        #expect(sections.map(\.id) == ["agent-claudeCode", "agent-codex"])
    }

    @Test
    func sectionsProjectGroupsAndOrdersByName() {
        let alpha = session(id: "a", workspaceName: "Alpha")
        let beta = session(id: "b", workspaceName: "Beta")
        let sections = SessionListPresenter.sections(
            from: [beta, alpha], group: .project, sort: .attention, staleThresholdSeconds: Self.stale, now: Self.now
        )
        #expect(sections.map(\.id) == ["project-Alpha", "project-Beta"])
    }

    @Test
    func projectGroupNameFallbackChain() {
        // workspaceName wins
        #expect(SessionListPresenter.projectGroupName(for: session(id: "w", workspaceName: "WS")) == "WS")
        // no jumpTarget → title's last "·" piece
        #expect(SessionListPresenter.projectGroupName(
            for: session(id: "t", title: "Codex · myproj", includeJumpTarget: false)) == "myproj")
        // no jumpTarget, blank title → tool.displayName
        #expect(SessionListPresenter.projectGroupName(
            for: session(id: "z", tool: .codex, title: "   ", includeJumpTarget: false)) == "Codex")
    }
}
