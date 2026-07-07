import Darwin
import Foundation

public enum BridgeSocketLocation {
    /// Stable per-user socket directory under ~/Library/Application Support.
    /// Unlike /tmp, this directory is not subject to periodic system cleanup.
    private static var stableDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("OpenIsland")
    }

    public static var defaultURL: URL {
        stableDirectoryURL.appendingPathComponent("bridge.sock")
    }

    /// Legacy path for backward compatibility with older hook binaries.
    public static var legacyURL: URL {
        URL(fileURLWithPath: "/tmp/open-island-\(getuid()).sock")
    }

    public static func currentURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["OPEN_ISLAND_SOCKET_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        if let legacyPath = environment["VIBE_ISLAND_SOCKET_PATH"], !legacyPath.isEmpty {
            return URL(fileURLWithPath: legacyPath)
        }

        return defaultURL
    }

    public static func uniqueTestURL() -> URL {
        URL(fileURLWithPath: "/tmp/open-island-test-\(UUID().uuidString).sock")
    }
}

public enum BridgeTransportError: Error, LocalizedError {
    case alreadyConnected
    case notConnected
    case malformedEnvelope
    case frameTooLarge
    case responseTimedOut
    case writeTimedOut
    case unknownMessageType(String)
    case listenerFailed(String)
    case socketPathTooLong
    case systemCallFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .alreadyConnected:
            "The bridge client is already connected."
        case .notConnected:
            "The bridge client is not connected."
        case .malformedEnvelope:
            "The bridge transport received malformed data."
        case .frameTooLarge:
            "The bridge transport received a frame exceeding the maximum size."
        case .responseTimedOut:
            "The local bridge timed out while waiting for a response."
        case .writeTimedOut:
            "The local bridge timed out while writing to a peer that stopped draining."
        case let .unknownMessageType(type):
            "The bridge transport received an unknown message type: \(type)."
        case let .listenerFailed(message):
            "The local bridge listener failed: \(message)"
        case .socketPathTooLong:
            "The Unix socket path is too long for `sockaddr_un`."
        case let .systemCallFailed(name, code):
            "\(name) failed with errno \(code)."
        }
    }
}

public struct BridgeHello: Equatable, Codable, Sendable {
    public var protocolVersion: Int
    public var serverLabel: String

    public init(protocolVersion: Int = 1, serverLabel: String = "local-bridge") {
        self.protocolVersion = protocolVersion
        self.serverLabel = serverLabel
    }
}

public enum BridgeClientRole: String, Codable, Sendable {
    case observer
}

public enum BridgeCommand: Equatable, Codable, Sendable {
    case registerClient(role: BridgeClientRole)
    case requestQuestion(sessionID: String, prompt: QuestionPrompt)
    case resolvePermission(sessionID: String, resolution: PermissionResolution)
    case answerQuestion(sessionID: String, response: QuestionPromptResponse)
    case processCodexHook(CodexHookPayload)
    case processClaudeHook(ClaudeHookPayload)
    case processOpenCodeHook(OpenCodeHookPayload)
    case processCursorHook(CursorHookPayload)
    case processGeminiHook(GeminiHookPayload)

    private enum CodingKeys: String, CodingKey {
        case type
        case role
        case sessionID
        case prompt
        case resolution
        case response
        case codexHook
        case claudeHook
        case openCodeHook
        case cursorHook
        case geminiHook
    }

    private enum CommandType: String, Codable {
        case registerClient
        case requestQuestion
        case resolvePermission
        case answerQuestion
        case processCodexHook
        case processClaudeHook
        case processOpenCodeHook
        case processCursorHook
        case processGeminiHook
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        guard let type = CommandType(rawValue: rawType) else {
            throw BridgeTransportError.unknownMessageType(rawType)
        }

        switch type {
        case .registerClient:
            self = .registerClient(role: try container.decode(BridgeClientRole.self, forKey: .role))
        case .requestQuestion:
            self = .requestQuestion(
                sessionID: try container.decode(String.self, forKey: .sessionID),
                prompt: try container.decode(QuestionPrompt.self, forKey: .prompt)
            )
        case .resolvePermission:
            self = .resolvePermission(
                sessionID: try container.decode(String.self, forKey: .sessionID),
                resolution: try container.decode(PermissionResolution.self, forKey: .resolution)
            )
        case .answerQuestion:
            self = .answerQuestion(
                sessionID: try container.decode(String.self, forKey: .sessionID),
                response: try container.decode(QuestionPromptResponse.self, forKey: .response)
            )
        case .processCodexHook:
            self = .processCodexHook(try container.decode(CodexHookPayload.self, forKey: .codexHook))
        case .processClaudeHook:
            self = .processClaudeHook(try container.decode(ClaudeHookPayload.self, forKey: .claudeHook))
        case .processOpenCodeHook:
            self = .processOpenCodeHook(try container.decode(OpenCodeHookPayload.self, forKey: .openCodeHook))
        case .processCursorHook:
            self = .processCursorHook(try container.decode(CursorHookPayload.self, forKey: .cursorHook))
        case .processGeminiHook:
            self = .processGeminiHook(try container.decode(GeminiHookPayload.self, forKey: .geminiHook))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .registerClient(role):
            try container.encode(CommandType.registerClient, forKey: .type)
            try container.encode(role, forKey: .role)
        case let .requestQuestion(sessionID, prompt):
            try container.encode(CommandType.requestQuestion, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(prompt, forKey: .prompt)
        case let .resolvePermission(sessionID, resolution):
            try container.encode(CommandType.resolvePermission, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(resolution, forKey: .resolution)
        case let .answerQuestion(sessionID, response):
            try container.encode(CommandType.answerQuestion, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(response, forKey: .response)
        case let .processCodexHook(payload):
            try container.encode(CommandType.processCodexHook, forKey: .type)
            try container.encode(payload, forKey: .codexHook)
        case let .processClaudeHook(payload):
            try container.encode(CommandType.processClaudeHook, forKey: .type)
            try container.encode(payload, forKey: .claudeHook)
        case let .processOpenCodeHook(payload):
            try container.encode(CommandType.processOpenCodeHook, forKey: .type)
            try container.encode(payload, forKey: .openCodeHook)
        case let .processCursorHook(payload):
            try container.encode(CommandType.processCursorHook, forKey: .type)
            try container.encode(payload, forKey: .cursorHook)
        case let .processGeminiHook(payload):
            try container.encode(CommandType.processGeminiHook, forKey: .type)
            try container.encode(payload, forKey: .geminiHook)
        }
    }
}

public enum BridgeResponse: Equatable, Codable, Sendable {
    case acknowledged
    case codexHookDirective(CodexHookDirective)
    case claudeHookDirective(ClaudeHookDirective)
    case openCodeHookDirective(OpenCodeHookDirective)
    case cursorHookDirective(CursorHookDirective)

    private enum CodingKeys: String, CodingKey {
        case type
        case directive
    }

    private enum ResponseType: String, Codable {
        case acknowledged
        case codexHookDirective
        case claudeHookDirective
        case openCodeHookDirective
        case cursorHookDirective
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        guard let type = ResponseType(rawValue: rawType) else {
            throw BridgeTransportError.unknownMessageType(rawType)
        }

        switch type {
        case .acknowledged:
            self = .acknowledged
        case .codexHookDirective:
            self = .codexHookDirective(try container.decode(CodexHookDirective.self, forKey: .directive))
        case .claudeHookDirective:
            self = .claudeHookDirective(try container.decode(ClaudeHookDirective.self, forKey: .directive))
        case .openCodeHookDirective:
            self = .openCodeHookDirective(try container.decode(OpenCodeHookDirective.self, forKey: .directive))
        case .cursorHookDirective:
            self = .cursorHookDirective(try container.decode(CursorHookDirective.self, forKey: .directive))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .acknowledged:
            try container.encode(ResponseType.acknowledged, forKey: .type)
        case let .codexHookDirective(directive):
            try container.encode(ResponseType.codexHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        case let .claudeHookDirective(directive):
            try container.encode(ResponseType.claudeHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        case let .openCodeHookDirective(directive):
            try container.encode(ResponseType.openCodeHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        case let .cursorHookDirective(directive):
            try container.encode(ResponseType.cursorHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        }
    }
}

public enum BridgeEnvelope: Equatable, Codable, Sendable {
    case hello(BridgeHello)
    case event(AgentEvent)
    case command(BridgeCommand)
    case response(BridgeResponse)

    private enum CodingKeys: String, CodingKey {
        case type
        case hello
        case event
        case command
        case response
    }

    private enum EnvelopeType: String, Codable {
        case hello
        case event
        case command
        case response
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        guard let type = EnvelopeType(rawValue: rawType) else {
            throw BridgeTransportError.unknownMessageType(rawType)
        }

        switch type {
        case .hello:
            self = .hello(try container.decode(BridgeHello.self, forKey: .hello))
        case .event:
            self = .event(try container.decode(AgentEvent.self, forKey: .event))
        case .command:
            self = .command(try container.decode(BridgeCommand.self, forKey: .command))
        case .response:
            self = .response(try container.decode(BridgeResponse.self, forKey: .response))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .hello(payload):
            try container.encode(EnvelopeType.hello, forKey: .type)
            try container.encode(payload, forKey: .hello)
        case let .event(payload):
            try container.encode(EnvelopeType.event, forKey: .type)
            try container.encode(payload, forKey: .event)
        case let .command(payload):
            try container.encode(EnvelopeType.command, forKey: .type)
            try container.encode(payload, forKey: .command)
        case let .response(payload):
            try container.encode(EnvelopeType.response, forKey: .type)
            try container.encode(payload, forKey: .response)
        }
    }
}

public enum BridgeCodec {
    private static let newline = UInt8(ascii: "\n")

    public static func encodeLine(_ envelope: BridgeEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        var data = try encoder.encode(envelope)
        data.append(newline)
        return data
    }

    /// Maximum size of a single NDJSON frame (and of the unterminated tail the
    /// buffer is allowed to accumulate). A peer that streams bytes without a
    /// newline would otherwise grow the buffer without bound (OOM); this caps it.
    public static let maxFrameByteCount = 4 * 1024 * 1024

    public static func decodeLines(from buffer: inout Data) throws -> [BridgeEnvelope] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        var messages: [BridgeEnvelope] = []

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)

            guard line.count <= maxFrameByteCount else {
                throw BridgeTransportError.frameTooLarge
            }

            guard !line.isEmpty else {
                continue
            }

            do {
                let message = try decoder.decode(BridgeEnvelope.self, from: Data(line))
                messages.append(message)
            } catch let error as BridgeTransportError {
                // Forward compatibility: a frame whose message/event type is
                // unknown (a newer peer's addition) is skipped, not fatal — one
                // unknown envelope must never kill the NDJSON stream or force a
                // reconnect. Any other transport error (e.g. genuinely malformed
                // JSON) is still surfaced.
                if case .unknownMessageType = error {
                    continue
                }
                throw error
            } catch {
                throw BridgeTransportError.malformedEnvelope
            }
        }

        // No complete frame yet: if the unterminated remainder already exceeds
        // the cap, the peer is sending an oversized/never-terminated frame.
        guard buffer.count <= maxFrameByteCount else {
            throw BridgeTransportError.frameTooLarge
        }

        return messages
    }
}

func withUnixSocketAddress<T>(
    path: String,
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(path.utf8)
    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)

    guard pathBytes.count < maxPathLength else {
        throw BridgeTransportError.socketPathTooLong
    }

    withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
        rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)

        for (index, byte) in pathBytes.enumerated() {
            rawBuffer[index] = byte
        }
    }

    let length = socklen_t(
        MemoryLayout.size(ofValue: address.sun_len) +
        MemoryLayout.size(ofValue: address.sun_family) +
        pathBytes.count + 1
    )

    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            try body(sockaddrPointer, length)
        }
    }
}

func makeSocketNonBlocking(_ fileDescriptor: Int32) throws {
    let currentFlags = fcntl(fileDescriptor, F_GETFL)
    guard currentFlags != -1 else {
        throw BridgeTransportError.systemCallFailed("fcntl(F_GETFL)", errno)
    }

    guard fcntl(fileDescriptor, F_SETFL, currentFlags | O_NONBLOCK) != -1 else {
        throw BridgeTransportError.systemCallFailed("fcntl(F_SETFL)", errno)
    }
}

func disableSocketSigPipe(_ fileDescriptor: Int32) throws {
    var enabled: Int32 = 1
    guard setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &enabled,
        socklen_t(MemoryLayout<Int32>.size)
    ) != -1 else {
        throw BridgeTransportError.systemCallFailed("setsockopt(SO_NOSIGPIPE)", errno)
    }
}

/// The effective uid of the process on the other end of a connected `AF_UNIX`
/// socket, or `nil` if it cannot be determined. Used to enforce a same-user
/// trust boundary on the control socket.
func peerEffectiveUID(of fileDescriptor: Int32) -> uid_t? {
    var uid = uid_t()
    var gid = gid_t()
    guard getpeereid(fileDescriptor, &uid, &gid) == 0 else {
        return nil
    }
    return uid
}

/// Whether a connecting peer should be trusted on the control socket.
/// Default-deny: the peer is accepted only when its effective uid can be
/// determined AND matches `expectedUID`. An indeterminate peer is rejected.
func isTrustedLocalPeer(_ fileDescriptor: Int32, expectedUID: uid_t = getuid()) -> Bool {
    guard let uid = peerEffectiveUID(of: fileDescriptor) else {
        return false
    }
    return uid == expectedUID
}

/// Default upper bound on how long a single `writeAll` may spend waiting for a
/// peer to drain its receive buffer. All server writes run on one serial queue,
/// so a peer that connects but never reads would otherwise wedge the entire
/// bridge (every client, every hook dispatch). On timeout `writeAll` throws so
/// the caller can drop that one peer instead of hanging the whole server.
public let bridgeWriteTimeout: TimeInterval = 5.0

func writeAll(
    _ data: Data,
    to fileDescriptor: Int32,
    timeout: TimeInterval = bridgeWriteTimeout
) throws {
    var remaining = data[...]
    // Monotonic deadline: unaffected by wall-clock changes (NTP, DST).
    let deadline = DispatchTime.now() + timeout

    while !remaining.isEmpty {
        let bytesWritten = remaining.withUnsafeBytes { rawBuffer -> Int in
            let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return write(fileDescriptor, baseAddress, rawBuffer.count)
        }

        if bytesWritten > 0 {
            remaining.removeFirst(bytesWritten)
            continue
        }

        if bytesWritten == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
            // Enforce the deadline before sleeping again so a peer that never
            // (or only slowly) drains cannot spin here forever.
            guard DispatchTime.now() < deadline else {
                throw BridgeTransportError.writeTimedOut
            }
            usleep(1_000)
            continue
        }

        throw BridgeTransportError.systemCallFailed("write", errno)
    }
}
