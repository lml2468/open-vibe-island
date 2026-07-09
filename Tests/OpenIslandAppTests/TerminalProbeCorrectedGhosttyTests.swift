import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Shared Ghostty jump-target correction incl. the Zellij guard (slice
/// `dedup-corrected-ghostty-jumptarget`, discovery finding #9 cluster A).
struct TerminalProbeCorrectedGhosttyTests {
    private func session(jumpTarget: JumpTarget?) -> AgentSession {
        AgentSession(
            id: "s1",
            title: "T",
            tool: .claudeCode,
            phase: .running,
            summary: "s",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            jumpTarget: jumpTarget
        )
    }

    private let snapshot = GhosttyTerminalSnapshot(
        sessionID: "ghostty-123",
        workingDirectory: "/tmp/work",
        title: "claude ~/work"
    )

    // MARK: - A1: applies the Ghostty corrections to a stale jumpTarget

    @Test
    func correctsStaleGhosttyJumpTarget() {
        let stale = JumpTarget(
            terminalApp: "iTerm",
            workspaceName: "old",
            paneTitle: "old title",
            workingDirectory: "/tmp/old",
            terminalSessionID: "old-id"
        )

        let corrected = TerminalProbeSupport.correctedGhosttyJumpTarget(
            for: session(jumpTarget: stale),
            snapshot: snapshot
        )

        #expect(corrected?.terminalApp == "Ghostty")
        #expect(corrected?.terminalSessionID == "ghostty-123")
        #expect(corrected?.workingDirectory == "/tmp/work")
        #expect(corrected?.paneTitle == "claude ~/work")
    }

    // MARK: - A2: the Zellij guard returns nil

    @Test
    func zellijJumpTargetIsLeftUntouched() {
        let zellij = JumpTarget(
            terminalApp: "zellij",
            workspaceName: "z",
            paneTitle: "z pane",
            workingDirectory: "/tmp/z",
            terminalSessionID: "zellij-pane-1"
        )
        #expect(TerminalProbeSupport.correctedGhosttyJumpTarget(
            for: session(jumpTarget: zellij),
            snapshot: snapshot
        ) == nil)

        // Case-insensitive.
        let zellijCased = JumpTarget(
            terminalApp: "Zellij",
            workspaceName: "z",
            paneTitle: "z pane",
            workingDirectory: "/tmp/z",
            terminalSessionID: "zellij-pane-1"
        )
        #expect(TerminalProbeSupport.correctedGhosttyJumpTarget(
            for: session(jumpTarget: zellijCased),
            snapshot: snapshot
        ) == nil)
    }

    // MARK: - A3: synthesizes a JumpTarget when the session has none

    @Test
    func synthesizesJumpTargetWhenNone() {
        let corrected = TerminalProbeSupport.correctedGhosttyJumpTarget(
            for: session(jumpTarget: nil),
            snapshot: snapshot
        )

        #expect(corrected != nil)
        #expect(corrected?.terminalApp == "Ghostty")
        #expect(corrected?.terminalSessionID == "ghostty-123")
        #expect(corrected?.workingDirectory == "/tmp/work")
        #expect(corrected?.paneTitle == "claude ~/work")
        #expect(corrected?.workspaceName == "work")
    }
}
