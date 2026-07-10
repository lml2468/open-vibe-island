import Foundation
import Testing
@testable import OpenIslandCore

/// Direct coverage for the extracted GeminiHookHandler via a fake AgentHookContext
/// that records emitted events + sent envelopes (slice `gemini-hook-handler`,
/// discovery finding #3). Pins the per-event mapping and the ensure/sync helper
/// behavior without a live socket — proving the AgentHookHandler seam.
struct GeminiHookHandlerTests {

    /// Records emit/send and serves a fixed set of sessions for `session`/`hasSession`.
    private final class FakeContext: AgentHookContext {
        var emitted: [AgentEvent] = []
        var sent: [(BridgeEnvelope, UUID)] = []
        var sessions: [String: AgentSession]

        init(sessions: [AgentSession] = []) {
            self.sessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        }

        func emit(_ event: AgentEvent) {
            emitted.append(event)
            // Mirror the server: apply so subsequent reads within one handle() see it.
            if case let .sessionStarted(p) = event {
                sessions[p.sessionID] = AgentSession(
                    id: p.sessionID, title: p.title, tool: p.tool, origin: p.origin ?? .live,
                    phase: p.initialPhase, summary: p.summary, updatedAt: p.timestamp,
                    jumpTarget: p.jumpTarget, geminiMetadata: p.geminiMetadata
                )
            }
        }
        func send(_ envelope: BridgeEnvelope, to clientID: UUID) { sent.append((envelope, clientID)) }
        func hasSession(id: String) -> Bool { sessions[id] != nil }
        func session(id: String) -> AgentSession? { sessions[id] }
    }

    private let client = UUID()

    private func payload(_ event: GeminiHookEventName, sessionID: String = "g1") -> GeminiHookPayload {
        GeminiHookPayload(
            cwd: "/tmp/\(sessionID)",
            hookEventName: event,
            sessionID: sessionID,
            transcriptPath: "/tmp/\(sessionID)/t.jsonl"
        )
    }

    // MARK: - A1: per-event mapping

    @Test
    func sessionStartEmitsSessionStartedAndAcknowledges() {
        let ctx = FakeContext()
        GeminiHookHandler().handle(payload(.sessionStart), from: client, context: ctx)

        guard case let .sessionStarted(p) = ctx.emitted.first else {
            #expect(Bool(false), "expected .sessionStarted"); return
        }
        #expect(p.tool == .geminiCLI)
        #expect(p.sessionID == "g1")
        #expect(ctx.sent.count == 1)
        if case .response(.acknowledged) = ctx.sent.first?.0 {} else {
            #expect(Bool(false), "expected an acknowledged response")
        }
    }

    @Test
    func beforeAgentEmitsRunningActivity() {
        let ctx = FakeContext()
        GeminiHookHandler().handle(payload(.beforeAgent), from: client, context: ctx)
        // ensure-session emits .sessionStarted first, then the .activityUpdated(.running).
        let activity = ctx.emitted.compactMap { event -> SessionActivityUpdated? in
            if case let .activityUpdated(a) = event { return a } else { return nil }
        }.first
        #expect(activity?.phase == .running)
        #expect(ctx.sent.count == 1)
    }

    @Test
    func afterAgentEmitsSessionCompleted() {
        let ctx = FakeContext(sessions: [geminiSession(id: "g1")])
        GeminiHookHandler().handle(payload(.afterAgent), from: client, context: ctx)
        #expect(ctx.emitted.contains { if case .sessionCompleted = $0 { true } else { false } })
    }

    @Test
    func sessionEndEmitsSessionCompletedWithSessionEndFlag() {
        let ctx = FakeContext(sessions: [geminiSession(id: "g1")])
        GeminiHookHandler().handle(payload(.sessionEnd), from: client, context: ctx)
        let completed = ctx.emitted.compactMap { event -> SessionCompleted? in
            if case let .sessionCompleted(c) = event { return c } else { return nil }
        }.first
        #expect(completed?.isSessionEnd == true)
    }

    @Test
    func notificationEmitsActivityWithCurrentPhase() {
        // Existing session in .running → notification preserves that phase.
        var running = geminiSession(id: "g1")
        running.phase = .running
        let ctx = FakeContext(sessions: [running])
        GeminiHookHandler().handle(payload(.notification), from: client, context: ctx)
        let activity = ctx.emitted.compactMap { event -> SessionActivityUpdated? in
            if case let .activityUpdated(a) = event { return a } else { return nil }
        }.first
        #expect(activity?.phase == .running)
    }

    // MARK: - A2: ensure/sync helpers

    @Test
    func ensureSessionEmitsSessionStartedOnlyWhenAbsent() {
        // Absent → beforeAgent triggers a .sessionStarted (ensure) before activity.
        let absentCtx = FakeContext()
        GeminiHookHandler().handle(payload(.beforeAgent), from: client, context: absentCtx)
        #expect(absentCtx.emitted.contains { if case .sessionStarted = $0 { true } else { false } })

        // Present → no .sessionStarted from ensure (only activity).
        let presentCtx = FakeContext(sessions: [geminiSession(id: "g1")])
        GeminiHookHandler().handle(payload(.beforeAgent), from: client, context: presentCtx)
        #expect(!presentCtx.emitted.contains { if case .sessionStarted = $0 { true } else { false } })
    }

    private func geminiSession(id: String) -> AgentSession {
        AgentSession(
            id: id, title: "T-\(id)", tool: .geminiCLI, origin: .live,
            phase: .completed, summary: "s", updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
