import Foundation
import Testing
@testable import OpenIslandCore

/// Regression cover for the `hasSession` fix: it previously checked
/// `localState` twice OR'd with itself (a copy-paste bug) and now also
/// consults `stateSnapshot`. A session known only via the pushed snapshot
/// must be reported present so requestQuestion/requestPermission aren't
/// silently dropped.
struct BridgeServerHasSessionTests {
    private func makeSession(id: String) -> AgentSession {
        AgentSession(
            id: id,
            title: "T",
            tool: .claudeCode,
            phase: .running,
            summary: "x",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    @Test
    func reportsSessionFromPushedSnapshot() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        #expect(server.hasSessionForTests(id: "snap-1") == false)

        server.updateStateSnapshot(SessionState(sessions: [makeSession(id: "snap-1")]))

        #expect(server.hasSessionForTests(id: "snap-1") == true)
        #expect(server.hasSessionForTests(id: "absent") == false)
    }
}
