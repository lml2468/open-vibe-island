import Foundation
import OpenIslandCore

/// Pure session-list bucketing/ranking derivation, extracted from `AppModel`
/// (slice `session-list-presenter`, discovery finding #8). Stateless — a function
/// of the session list, the current time, the completed-stale threshold, and a
/// live-attachment-key resolver (the one coordinator dependency, injected as a
/// closure so the presenter needs no AppModel/coordinator reference). This keeps
/// the ranking directly unit-testable with a fixed `now`.
enum SessionListPresenter {
    // RED STUBS — wrong values so the failing-first tests compile and fail on
    // assertion. Replaced in Green with the verbatim bodies from AppModel.

    static func displayPriority(
        for session: AgentSession,
        now: Date,
        staleThresholdSeconds: TimeInterval
    ) -> Int {
        0
    }

    static func buckets(
        from sessions: [AgentSession],
        now: Date,
        staleThresholdSeconds: TimeInterval,
        liveAttachmentKey: (AgentSession) -> String?
    ) -> (primary: [AgentSession], overflow: [AgentSession]) {
        ([], [])
    }
}
