import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Direct unit coverage for the pure session bucketing/ranking pipeline extracted
/// from AppModel (slice `session-list-presenter`, discovery finding #8). Before
/// this the ranking + liveAttachmentKey dedup were only exercised end-to-end
/// through AppModel; these pin the scoring, the primary/overflow split, and the
/// dedup directly with a fixed `now`.
@MainActor
struct SessionListPresenterTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let stale: TimeInterval = 3_600

    private func session(
        id: String,
        phase: SessionPhase = .running,
        updatedAt: Date = SessionListPresenterTests.now,
        processAlive: Bool = false,
        hookManaged: Bool = true,
        jumpTarget: JumpTarget? = nil
    ) -> AgentSession {
        var s = AgentSession(
            id: id,
            title: "T-\(id)",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "s",
            updatedAt: updatedAt,
            jumpTarget: jumpTarget
        )
        s.isProcessAlive = processAlive
        s.isHookManaged = hookManaged
        return s
    }

    // MARK: - A1: displayPriority scoring

    @Test
    func attentionSessionOutranksIdleCompleted() {
        let attention = session(id: "att", phase: .waitingForApproval)
        let completed = session(id: "done", phase: .completed)
        let attScore = SessionListPresenter.displayPriority(for: attention, now: Self.now, staleThresholdSeconds: Self.stale)
        let doneScore = SessionListPresenter.displayPriority(for: completed, now: Self.now, staleThresholdSeconds: Self.stale)
        #expect(attScore > doneScore)
    }

    @Test
    func freshCompletedOutranksStaleCompleted() {
        let fresh = session(id: "fresh", phase: .completed, updatedAt: Self.now)
        let staleSession = session(id: "stale", phase: .completed, updatedAt: Self.now.addingTimeInterval(-7_200))
        var staleEnded = staleSession
        staleEnded.isSessionEnded = true
        let freshScore = SessionListPresenter.displayPriority(for: fresh, now: Self.now, staleThresholdSeconds: Self.stale)
        let staleScore = SessionListPresenter.displayPriority(for: staleEnded, now: Self.now, staleThresholdSeconds: Self.stale)
        #expect(freshScore > staleScore)
    }

    @Test
    func liveProcessAddsScore() {
        let alive = session(id: "alive", phase: .running, processAlive: true)
        let dead = session(id: "dead", phase: .running, processAlive: false)
        #expect(SessionListPresenter.displayPriority(for: alive, now: Self.now, staleThresholdSeconds: Self.stale)
            > SessionListPresenter.displayPriority(for: dead, now: Self.now, staleThresholdSeconds: Self.stale))
    }

    // MARK: - A2: buckets ranking + primary/overflow split

    @Test
    func bucketsRankPrimaryByPriorityAndExcludeInvisible() {
        let attention = session(id: "att", phase: .waitingForApproval)          // visible (attention)
        let running = session(id: "run", phase: .running, processAlive: true)   // visible (alive)
        var endedInvisible = session(id: "gone", phase: .running, processAlive: false, hookManaged: true)
        endedInvisible.isSessionEnded = true                                    // hook-managed + ended → invisible

        let result = SessionListPresenter.buckets(
            from: [running, endedInvisible, attention],
            now: Self.now,
            staleThresholdSeconds: Self.stale,
            liveAttachmentKey: { _ in nil }
        )
        // attention (10k+) ranks before running; ended/invisible excluded from primary.
        #expect(result.primary.map(\.id) == ["att", "run"])
        #expect(!result.primary.contains { $0.id == "gone" })
    }

    // MARK: - A3: liveAttachmentKey dedup

    @Test
    func bucketsDedupPrimaryBySharedLiveAttachmentKeyKeepingHigherRanked() {
        let higher = session(id: "hi", phase: .waitingForApproval)             // higher score
        let lower = session(id: "lo", phase: .running, processAlive: true)     // lower score, same key
        let result = SessionListPresenter.buckets(
            from: [lower, higher],
            now: Self.now,
            staleThresholdSeconds: Self.stale,
            liveAttachmentKey: { _ in "shared-key" }
        )
        // Only the higher-ranked claimant of the shared key stays in primary.
        #expect(result.primary.map(\.id) == ["hi"])
        #expect(result.overflow.map(\.id) == ["lo"])
    }

    @Test
    func bucketsNilKeyNeverDedups() {
        let a = session(id: "a", phase: .waitingForApproval)
        let b = session(id: "b", phase: .waitingForApproval)
        let result = SessionListPresenter.buckets(
            from: [a, b],
            now: Self.now,
            staleThresholdSeconds: Self.stale,
            liveAttachmentKey: { _ in nil }
        )
        #expect(Set(result.primary.map(\.id)) == ["a", "b"])
    }
}
