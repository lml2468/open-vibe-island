import Foundation

/// The capability surface `BridgeServer` exposes to an extracted per-agent hook
/// handler. Intentionally **synchronous** and minimal — a handler may only emit
/// events, send envelopes, and read session existence/state through this seam, so
/// handler code cannot hop off the server's serial queue or reach transport
/// internals. (Slice `gemini-hook-handler`, discovery finding #3 — the
/// AgentHookHandler proof-of-concept.)
protocol AgentHookContext: AnyObject {
    func emit(_ event: AgentEvent)
    func send(_ envelope: BridgeEnvelope, to clientID: UUID)
    func hasSession(id: String) -> Bool
    /// Reads the server's working (`localState`) session, mirroring the handlers'
    /// direct `localState.session(id:)` reads. Distinct from `hasSession`, which
    /// also considers the AppModel-pushed snapshot.
    func session(id: String) -> AgentSession?
}

/// A per-agent hook handler: maps that agent's decoded hook payload to bridge
/// events/responses via an `AgentHookContext`. Proof-of-concept seam — currently
/// only `GeminiHookHandler` adopts it.
protocol AgentHookHandler {
    associatedtype Payload
    func handle(_ payload: Payload, from clientID: UUID, context: AgentHookContext)
}

/// Maps Gemini CLI hook events to bridge events. Extracted verbatim from
/// `BridgeServer.handleGeminiHook` behind the `AgentHookContext` seam. Gemini has no
/// pending-interaction / permission round-trip state, so it needs nothing from the
/// server beyond emit/send/session reads.
struct GeminiHookHandler: AgentHookHandler {
    // RED STUB — does nothing; replaced in Green.
    func handle(_ payload: GeminiHookPayload, from clientID: UUID, context: AgentHookContext) {
    }
}
