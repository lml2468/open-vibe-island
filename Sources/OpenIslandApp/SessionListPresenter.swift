import Foundation
import OpenIslandCore

/// Pure session-list bucketing/ranking derivation, extracted from `AppModel`
/// (slice `session-list-presenter`, discovery finding #8). Stateless — a function
/// of the session list, the current time, the completed-stale threshold, and a
/// live-attachment-key resolver (the one coordinator dependency, injected as a
/// closure so the presenter needs no AppModel/coordinator reference). This keeps
/// the ranking directly unit-testable with a fixed `now`.
enum SessionListPresenter {
    static func buckets(
        from sessions: [AgentSession],
        now: Date,
        staleThresholdSeconds: TimeInterval,
        liveAttachmentKey: (AgentSession) -> String?
    ) -> (primary: [AgentSession], overflow: [AgentSession]) {
        let rankedSessions = sessions.sorted { lhs, rhs in
            let lhsScore = displayPriority(for: lhs, now: now, staleThresholdSeconds: staleThresholdSeconds)
            let rhsScore = displayPriority(for: rhs, now: now, staleThresholdSeconds: staleThresholdSeconds)

            if lhsScore == rhsScore {
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                return lhs.islandActivityDate > rhs.islandActivityDate
            }

            return lhsScore > rhsScore
        }

        var primary: [AgentSession] = []
        var claimedLiveAttachmentKeys: Set<String> = []

        for session in rankedSessions where session.isVisibleInIsland {
            guard !session.isSubagentSession else { continue }

            if let liveAttachmentKey = liveAttachmentKey(session) {
                guard claimedLiveAttachmentKeys.insert(liveAttachmentKey).inserted else {
                    continue
                }
            }

            primary.append(session)
        }

        let primaryIDs = Set(primary.map(\.id))
        let overflow = rankedSessions.filter { !primaryIDs.contains($0.id) && !$0.isSubagentSession }
        return (primary, overflow)
    }

    static func displayPriority(
        for session: AgentSession,
        now: Date,
        staleThresholdSeconds: TimeInterval
    ) -> Int {
        var score = 0

        let presence = session.islandPresence(at: now)

        if session.isProcessAlive {
            score += presence == .inactive ? 3_000 : 12_000
        } else if session.isDemoSession || session.phase.requiresAttention {
            score += 6_000
        }

        if session.phase.requiresAttention {
            score += 10_000
        }

        if session.currentToolName?.isEmpty == false {
            score += 6_000
        }

        if session.jumpTarget != nil {
            score += 4_000
        }

        switch session.phase {
        case .running:
            score += 2_000
        case .waitingForApproval:
            score += 1_500
        case .waitingForAnswer:
            score += 1_200
        case .completed:
            score += 600
        }

        if session.isStaleCompletedForIsland(at: now, threshold: staleThresholdSeconds) {
            score -= 900
        }

        let age = now.timeIntervalSince(session.islandActivityDate)
        switch age {
        case ..<120:
            score += 500
        case ..<900:
            score += 250
        case ..<3_600:
            score += 120
        case ..<21_600:
            score += 40
        default:
            break
        }

        return score
    }

    // MARK: - Sectioning

    static func sections(
        from surfaced: [AgentSession],
        group: IslandSessionGroup,
        sort: IslandSessionSort,
        staleThresholdSeconds: TimeInterval,
        now: Date
    ) -> [IslandSessionSection] {
        let sessions = sortSessions(surfaced, by: sort)
        switch group {
        case .none:
            return [
                IslandSessionSection(
                    id: "all",
                    title: "island.section.sessions",
                    sessions: sessions
                )
            ]
        case .state:
            return stateGroupedSections(from: sessions, staleThresholdSeconds: staleThresholdSeconds, now: now)
        case .agent:
            return AgentTool.allCases.compactMap { tool in
                let list = sessions.filter { $0.tool == tool }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "agent-\(tool.rawValue)", title: tool.displayName, sessions: list)
            }
        case .project:
            let names = Set(sessions.map(projectGroupName(for:))).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            return names.compactMap { name in
                let list = sessions.filter { projectGroupName(for: $0) == name }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "project-\(name)", title: name, sessions: list)
            }
        }
    }

    static func sortSessions(
        _ sessions: [AgentSession],
        by sort: IslandSessionSort
    ) -> [AgentSession] {
        switch sort {
        case .attention:
            return sessions
        case .lastUpdate:
            return sessions.sorted { lhs, rhs in
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.islandActivityDate > rhs.islandActivityDate
            }
        }
    }

    static func stateGroupedSections(
        from sessions: [AgentSession],
        staleThresholdSeconds: TimeInterval,
        now: Date
    ) -> [IslandSessionSection] {
        let definitions: [(id: String, title: String, include: (AgentSession) -> Bool)] = [
            ("approval", "island.section.needsApproval", { $0.phase == .waitingForApproval }),
            ("answer", "island.section.needsAnswer", { $0.phase == .waitingForAnswer }),
            ("running", "island.section.inProgress", { $0.phase == .running }),
            ("done", "island.section.justDone", { session in
                session.phase == .completed
                    && !session.isStaleCompletedForIsland(at: now, threshold: staleThresholdSeconds)
            }),
            ("idle", "island.section.idle", { session in
                session.phase == .completed
                    && session.isStaleCompletedForIsland(at: now, threshold: staleThresholdSeconds)
            }),
        ]

        return definitions.compactMap { definition in
            let list = sessions.filter(definition.include)
            guard !list.isEmpty else { return nil }
            return IslandSessionSection(id: "state-\(definition.id)", title: definition.title, sessions: list)
        }
    }

    static func projectGroupName(for session: AgentSession) -> String {
        if let workspace = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return workspace
        }

        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return session.tool.displayName }

        let pieces = title.split(separator: "·", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return pieces.last?.isEmpty == false ? pieces.last! : title
    }
}
