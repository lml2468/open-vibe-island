import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Characterization of AppModel's session sectioning branches that lacked direct
/// coverage (slice `sectioning-characterization-tests`, discovery finding #8):
/// `.agent`/`.project`/`.none` grouping and `.attention` sort. These pin behavior
/// the follow-on `SessionListPresenter` sectioning extraction must preserve; they
/// pass on the current tree and drive through the public `islandSessionSections`.
@MainActor
@Suite(.serialized)
struct SessionSectioningTests {
    init() {
        [
            "appearance.island.v8.sessionGroup",
            "appearance.island.v8.sessionSort",
            "appearance.island.v8.notch.sessionGroup",
            "appearance.island.v8.notch.sessionSort",
            "appearance.island.v8.topBar.sessionGroup",
            "appearance.island.v8.topBar.sessionSort",
        ].forEach(UserDefaults.standard.removeObject(forKey:))
    }

    private func session(
        id: String,
        tool: AgentTool = .codex,
        updatedAt: Date,
        workspaceName: String? = nil,
        title: String? = nil,
        includeJumpTarget: Bool = true
    ) -> AgentSession {
        var s = AgentSession(
            id: id,
            title: title ?? "T-\(id)",
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "s",
            updatedAt: updatedAt,
            jumpTarget: includeJumpTarget
                ? JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: workspaceName ?? id,
                    paneTitle: "pane-\(id)"
                )
                : nil
        )
        s.isProcessAlive = true   // surfaced in the island
        return s
    }

    // MARK: - A1: .agent grouping

    @Test
    func agentGroupingSectionsPerToolInAllCasesOrder() {
        let now = Date()
        let model = AppModel()
        model.islandSessionGroup = .agent

        let codex = session(id: "cx", tool: .codex, updatedAt: now)
        let claude = session(id: "cl", tool: .claudeCode, updatedAt: now)
        model.state = SessionState(sessions: [codex, claude])

        let sections = model.islandSessionSections
        // AgentTool.allCases order: claudeCode precedes codex.
        #expect(sections.map(\.id) == ["agent-claudeCode", "agent-codex"])
        #expect(sections.map(\.title) == ["Claude Code", "Codex"])
        // no section for a tool with no sessions
        #expect(!sections.contains { $0.id == "agent-cursor" })
        #expect(sections.first { $0.id == "agent-codex" }?.sessions.map(\.id) == ["cx"])
    }

    // MARK: - A2: .project grouping + projectGroupName fallbacks

    @Test
    func projectGroupingSectionsOrderedByNameWithFallbacks() {
        let now = Date()
        let model = AppModel()
        model.islandSessionGroup = .project

        let alpha = session(id: "a", updatedAt: now, workspaceName: "Alpha")
        let beta = session(id: "b", updatedAt: now, workspaceName: "Beta")
        // no jumpTarget → falls back to title's last "·" piece → "proj"
        let fallback = session(id: "c", updatedAt: now, title: "Codex · proj", includeJumpTarget: false)
        model.state = SessionState(sessions: [beta, fallback, alpha])

        let sections = model.islandSessionSections
        // localizedStandardCompare asc: Alpha, Beta, proj
        #expect(sections.map(\.id) == ["project-Alpha", "project-Beta", "project-proj"])
        #expect(sections.map(\.title) == ["Alpha", "Beta", "proj"])
        #expect(sections.first { $0.id == "project-Alpha" }?.sessions.map(\.id) == ["a"])
        #expect(sections.first { $0.id == "project-proj" }?.sessions.map(\.id) == ["c"])
    }

    @Test
    func projectGroupNameFallsBackToToolDisplayNameWhenNoWorkspaceOrTitlePiece() {
        let now = Date()
        let model = AppModel()
        model.islandSessionGroup = .project

        // no jumpTarget, title has no "·" → last piece is the whole title.
        // Use a whitespace-only title so the guard fails → tool.displayName.
        let blank = session(id: "x", tool: .codex, updatedAt: now, title: "   ", includeJumpTarget: false)
        model.state = SessionState(sessions: [blank])

        let sections = model.islandSessionSections
        #expect(sections.map(\.id) == ["project-Codex"])
        #expect(sections.first?.title == "Codex")
    }

    // MARK: - A3: .none grouping

    @Test
    func noneGroupingYieldsSingleAllSection() {
        let now = Date()
        let model = AppModel()
        model.islandSessionGroup = .none

        let one = session(id: "one", updatedAt: now)
        let two = session(id: "two", updatedAt: now.addingTimeInterval(-30))
        model.state = SessionState(sessions: [one, two])

        let sections = model.islandSessionSections
        #expect(sections.count == 1)
        #expect(sections.first?.id == "all")
        #expect(sections.first?.title == "island.section.sessions")
        #expect(Set(sections.first?.sessions.map(\.id) ?? []) == ["one", "two"])
    }

    // MARK: - A4: .attention sort is identity (vs .lastUpdate reordering)

    @Test
    func attentionSortPreservesSurfacedOrderUnlikeLastUpdate() {
        let now = Date()

        // Make surfaced (priority) order DIVERGE from activity-date order: an OLDER
        // waiting-for-approval session outranks a NEWER running one by displayPriority,
        // so surfacedSessions = [attnOlder, runNewer] while .lastUpdate would put the
        // newer one first. This distinguishes .attention (identity) from any re-sort.
        var attnOlder = session(id: "attn-older", updatedAt: now.addingTimeInterval(-100))
        attnOlder.phase = .waitingForApproval
        attnOlder.permissionRequest = PermissionRequest(title: "Approve", summary: "run", affectedPath: "/tmp")
        let runNewer = session(id: "run-newer", updatedAt: now)   // .running (from helper)

        let attentionModel = AppModel()
        attentionModel.islandSessionGroup = .none
        attentionModel.islandSessionSort = .attention
        attentionModel.state = SessionState(sessions: [attnOlder, runNewer])
        let attentionOrder = attentionModel.islandSessionSections.first?.sessions.map(\.id) ?? []
        let surfacedOrder = attentionModel.surfacedSessions.map(\.id)

        let lastUpdateModel = AppModel()
        lastUpdateModel.islandSessionGroup = .none
        lastUpdateModel.islandSessionSort = .lastUpdate
        lastUpdateModel.state = SessionState(sessions: [attnOlder, runNewer])
        let lastUpdateOrder = lastUpdateModel.islandSessionSections.first?.sessions.map(\.id) ?? []

        // Priority-ranked surfaced order puts the attention session first (older).
        #expect(surfacedOrder == ["attn-older", "run-newer"])
        // .attention is identity → equals surfaced order (attention-first).
        #expect(attentionOrder == ["attn-older", "run-newer"])
        // .lastUpdate re-sorts by activity date desc → newer first, diverging from
        // surfaced order — so the identity assertion above genuinely pins "no re-sort".
        #expect(lastUpdateOrder == ["run-newer", "attn-older"])
    }
}
