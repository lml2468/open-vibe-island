import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Shared Terminal.app jump-target correction + nonEmptyValue (slice
/// `dedup-corrected-terminal-jumptarget`, discovery finding #9 cluster A).
struct TerminalProbeCorrectedTargetTests {
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

    // MARK: - A1: applies the corrections

    @Test
    func correctsStaleTerminalJumpTarget() {
        let stale = JumpTarget(
            terminalApp: "iTerm",              // wrong app → should become "Terminal"
            workspaceName: "ws",
            paneTitle: "old title",
            terminalTTY: "/dev/ttys999"        // wrong tty → should become snapshot.tty
        )
        let snapshot = TerminalTabSnapshot(tty: "/dev/ttys001", customTitle: "New Title")

        let corrected = TerminalProbeSupport.correctedTerminalJumpTarget(
            for: session(jumpTarget: stale),
            snapshot: snapshot
        )

        #expect(corrected?.terminalApp == "Terminal")
        #expect(corrected?.terminalTTY == "/dev/ttys001")
        #expect(corrected?.paneTitle == "New Title")
    }

    // MARK: - A2: nil when nothing changed / no jumpTarget

    @Test
    func returnsNilWhenAlreadyCorrect() {
        let alreadyCorrect = JumpTarget(
            terminalApp: "Terminal",
            workspaceName: "ws",
            paneTitle: "Same Title",
            terminalTTY: "/dev/ttys001"
        )
        let snapshot = TerminalTabSnapshot(tty: "/dev/ttys001", customTitle: "Same Title")

        let corrected = TerminalProbeSupport.correctedTerminalJumpTarget(
            for: session(jumpTarget: alreadyCorrect),
            snapshot: snapshot
        )

        #expect(corrected == nil)
    }

    @Test
    func returnsNilWhenNoJumpTarget() {
        let snapshot = TerminalTabSnapshot(tty: "/dev/ttys001", customTitle: "Title")
        let corrected = TerminalProbeSupport.correctedTerminalJumpTarget(
            for: session(jumpTarget: nil),
            snapshot: snapshot
        )
        #expect(corrected == nil)
    }

    // MARK: - A3: shared nonEmptyValue

    @Test
    func nonEmptyValueTrimsAndNilsEmpties() {
        #expect(TerminalProbeSupport.nonEmptyValue("  hi \n") == "hi")
        #expect(TerminalProbeSupport.nonEmptyValue("plain") == "plain")
        #expect(TerminalProbeSupport.nonEmptyValue("   ") == nil)
        #expect(TerminalProbeSupport.nonEmptyValue(nil) == nil)
    }
}
