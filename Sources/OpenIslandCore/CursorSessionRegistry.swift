import Foundation

public struct CursorTrackedSessionRecord: Equatable, Codable, Sendable {
    public var sessionID: String
    public var title: String
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var summary: String
    public var phase: SessionPhase
    public var updatedAt: Date
    public var firstSeenAt: Date?
    public var jumpTarget: JumpTarget?
    public var cursorMetadata: CursorSessionMetadata?

    public init(
        sessionID: String,
        title: String,
        origin: SessionOrigin? = nil,
        attachmentState: SessionAttachmentState = .stale,
        summary: String,
        phase: SessionPhase,
        updatedAt: Date,
        firstSeenAt: Date? = nil,
        jumpTarget: JumpTarget? = nil,
        cursorMetadata: CursorSessionMetadata? = nil
    ) {
        self.sessionID = sessionID
        self.title = title
        self.origin = origin
        self.attachmentState = attachmentState
        self.summary = summary
        self.phase = phase
        self.updatedAt = updatedAt
        self.firstSeenAt = firstSeenAt
        self.jumpTarget = jumpTarget
        self.cursorMetadata = cursorMetadata
    }

    public init(session: AgentSession) {
        self.init(
            sessionID: session.id,
            title: session.title,
            origin: session.origin,
            attachmentState: session.attachmentState,
            summary: session.summary,
            phase: session.phase,
            updatedAt: session.updatedAt,
            firstSeenAt: session.firstSeenAt,
            jumpTarget: session.jumpTarget,
            cursorMetadata: session.cursorMetadata
        )
    }

    public var session: AgentSession {
        AgentSession(
            id: sessionID,
            title: title,
            tool: .cursor,
            origin: origin,
            attachmentState: attachmentState,
            phase: phase,
            summary: summary,
            updatedAt: updatedAt,
            firstSeenAt: firstSeenAt,
            jumpTarget: jumpTarget,
            cursorMetadata: cursorMetadata
        )
    }

    public var restorableSession: AgentSession {
        var session = session
        session.attachmentState = .stale
        return session
    }
}

public extension CursorTrackedSessionRecord {
    var shouldRestoreToLiveState: Bool {
        origin != .demo
    }
}

public final class CursorSessionRegistry: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultDirectoryURL: URL {
        CodexSessionStore.defaultDirectoryURL
    }

    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("cursor-session-registry.json")
    }

    public init(
        fileURL: URL = CursorSessionRegistry.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> [CursorTrackedSessionRecord] {
        try SessionRegistryStore.load(from: fileURL, fileManager: fileManager)
    }

    public func save(_ records: [CursorTrackedSessionRecord]) throws {
        try SessionRegistryStore.save(records, to: fileURL, fileManager: fileManager)
    }
}
