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
    func handle(_ payload: GeminiHookPayload, from clientID: UUID, context: AgentHookContext) {
        switch payload.hookEventName {
        case .sessionStart:
            context.emit(
                .sessionStarted(
                    SessionStarted(
                        sessionID: payload.sessionID,
                        title: payload.sessionTitle,
                        tool: .geminiCLI,
                        origin: .live,
                        initialPhase: .completed,
                        summary: payload.implicitSummary,
                        timestamp: .now,
                        jumpTarget: payload.defaultJumpTarget,
                        geminiMetadata: payload.defaultGeminiMetadata.isEmpty ? nil : payload.defaultGeminiMetadata
                    )
                )
            )
            context.send(.response(.acknowledged), to: clientID)

        case .beforeAgent:
            ensureSessionExists(for: payload, context: context)
            synchronizeJumpTarget(for: payload, context: context)
            synchronizeMetadata(for: payload, context: context)
            context.emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.implicitSummary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            context.send(.response(.acknowledged), to: clientID)

        case .afterAgent:
            ensureSessionExists(for: payload, context: context)
            synchronizeJumpTarget(for: payload, context: context)
            synchronizeMetadata(for: payload, context: context)
            context.emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: payload.implicitSummary,
                        timestamp: .now
                    )
                )
            )
            context.send(.response(.acknowledged), to: clientID)

        case .sessionEnd:
            ensureSessionExists(for: payload, context: context)
            synchronizeJumpTarget(for: payload, context: context)
            synchronizeMetadata(for: payload, context: context)
            context.emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: payload.reason.map { "Gemini CLI session ended: \($0)." } ?? payload.implicitSummary,
                        timestamp: .now,
                        isInterrupt: true,
                        isSessionEnd: true
                    )
                )
            )
            context.send(.response(.acknowledged), to: clientID)

        case .notification:
            ensureSessionExists(for: payload, context: context)
            synchronizeJumpTarget(for: payload, context: context)
            synchronizeMetadata(for: payload, context: context)

            let currentPhase = context.session(id: payload.sessionID)?.phase ?? .completed
            context.emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.notificationSummary,
                        phase: currentPhase,
                        timestamp: .now
                    )
                )
            )

            context.send(.response(.acknowledged), to: clientID)
        }
    }

    private func ensureSessionExists(for payload: GeminiHookPayload, context: AgentHookContext) {
        guard !context.hasSession(id: payload.sessionID) else {
            return
        }

        context.emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .geminiCLI,
                    origin: .live,
                    initialPhase: .completed,
                    summary: payload.hookEventName == .notification ? payload.notificationSummary : payload.implicitSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    geminiMetadata: payload.defaultGeminiMetadata.isEmpty ? nil : payload.defaultGeminiMetadata
                )
            )
        )
    }

    private func synchronizeJumpTarget(for payload: GeminiHookPayload, context: AgentHookContext) {
        guard let existingSession = context.session(id: payload.sessionID) else {
            return
        }

        let jumpTarget = BridgeServer.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: payload.defaultJumpTarget,
            existing: existingSession.jumpTarget
        )

        guard existingSession.jumpTarget != jumpTarget else {
            return
        }

        context.emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: jumpTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeMetadata(for payload: GeminiHookPayload, context: AgentHookContext) {
        guard let existingSession = context.session(id: payload.sessionID) else {
            return
        }

        let update = payload.defaultGeminiMetadata
        let merged = GeminiSessionMetadata(
            transcriptPath: update.transcriptPath ?? existingSession.geminiMetadata?.transcriptPath,
            initialUserPrompt: existingSession.geminiMetadata?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existingSession.geminiMetadata?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existingSession.geminiMetadata?.lastAssistantMessage,
            lastAssistantMessageBody: update.lastAssistantMessageBody ?? existingSession.geminiMetadata?.lastAssistantMessageBody
        )
        guard !merged.isEmpty else {
            return
        }

        guard existingSession.geminiMetadata != merged else {
            return
        }

        context.emit(
            .geminiSessionMetadataUpdated(
                GeminiSessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    geminiMetadata: merged,
                    timestamp: .now
                )
            )
        )
    }
}
