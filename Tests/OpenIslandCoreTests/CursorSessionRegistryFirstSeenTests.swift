import Foundation
import Testing
@testable import OpenIslandCore

struct CursorSessionRegistryFirstSeenTests {
    @Test
    func recordPreservesFirstSeenAt() {
        let firstSeen = Date(timeIntervalSince1970: 500)
        let updated = Date(timeIntervalSince1970: 900)

        let record = CursorTrackedSessionRecord(
            sessionID: "cursor-1",
            title: "Cursor",
            summary: "s",
            phase: .running,
            updatedAt: updated,
            firstSeenAt: firstSeen
        )

        // firstSeenAt must survive into the materialized session so the grid's
        // stable order is preserved across restores.
        #expect(record.session.firstSeenAt == firstSeen)
    }

    @Test
    func recordFromSessionPreservesFirstSeenAt() {
        let firstSeen = Date(timeIntervalSince1970: 500)
        let updated = Date(timeIntervalSince1970: 900)
        let session = AgentSession(
            id: "cursor-2",
            title: "Cursor",
            tool: .cursor,
            phase: .running,
            summary: "s",
            updatedAt: updated,
            firstSeenAt: firstSeen
        )

        let record = CursorTrackedSessionRecord(session: session)
        #expect(record.firstSeenAt == firstSeen)
        #expect(record.session.firstSeenAt == firstSeen)
    }

    @Test
    func legacyRecordWithoutFirstSeenAtDecodes() throws {
        // Records persisted before firstSeenAt existed must still decode (the
        // field is optional); the session falls back to updatedAt.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyJSON = """
        {
          "sessionID": "cursor-legacy",
          "title": "Cursor",
          "attachmentState": "stale",
          "summary": "s",
          "phase": "running",
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let record = try decoder.decode(CursorTrackedSessionRecord.self, from: legacyJSON)
        #expect(record.firstSeenAt == nil)
        let expected = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")
        #expect(record.session.firstSeenAt == expected)
    }
}
