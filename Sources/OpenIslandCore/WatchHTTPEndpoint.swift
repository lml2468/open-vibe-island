import Foundation
import Network
import os

// MARK: - SSE Event Types

/// Events pushed to connected iPhone clients via Server-Sent Events.
public enum WatchSSEEvent: Sendable {
    case permissionRequested(WatchPermissionEvent)
    case questionAsked(WatchQuestionEvent)
    case sessionCompleted(WatchCompletionEvent)
    /// Sent when an actionable request (permission/question) has been resolved on the Mac side.
    case actionableStateResolved(WatchResolvedEvent)

    func sseString() -> String {
        switch self {
        case let .permissionRequested(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: permissionRequested\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .questionAsked(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: questionAsked\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .sessionCompleted(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: sessionCompleted\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .actionableStateResolved(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: actionableStateResolved\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        }
    }
}

public struct WatchPermissionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var title: String
    public var summary: String
    public var workingDirectory: String?
    public var primaryAction: String
    public var secondaryAction: String
    public var requestID: String
}

public struct WatchQuestionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var title: String
    public var options: [String]
    public var requestID: String
}

public struct WatchCompletionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var summary: String
}

// MARK: - Resolved Event

/// Sent via SSE when an actionable request has been resolved on the Mac side.
public struct WatchResolvedEvent: Codable, Sendable {
    public var requestID: String
    public var sessionID: String

    public init(requestID: String, sessionID: String) {
        self.requestID = requestID
        self.sessionID = sessionID
    }
}

// MARK: - Resolution

public struct WatchResolutionRequest: Codable, Sendable {
    public var requestID: String
    public var action: String
}

// MARK: - Pairing

public struct WatchPairRequest: Codable, Sendable {
    public var code: String
}

public struct WatchPairResponse: Codable, Sendable {
    public var token: String
}

// MARK: - Status

public struct WatchStatusResponse: Codable, Sendable {
    public var connected: Bool
    public var activeSessionCount: Int
}

// MARK: - Resolution Handler

/// Callback invoked when the Watch/iPhone submits a resolution via `/resolution`.
public typealias WatchResolutionHandler = @Sendable (WatchResolutionRequest) -> Void

/// Callback to query current active session count for `/status`.
public typealias WatchActiveSessionCountProvider = @Sendable () -> Int

// MARK: - WatchHTTPEndpoint

/// A lightweight HTTP server embedded in the macOS app that enables iPhone/Watch communication.
///
/// Uses `NWListener` for TCP + Bonjour advertising of `_openisland._tcp`.
/// Implements a minimal HTTP/1.1 parser for 4 endpoints:
/// - `POST /pair` — submit 4-digit pairing code, receive session token
/// - `GET /events` — SSE stream of agent events
/// - `POST /resolution` — submit Watch action decisions
/// - `GET /status` — connection and session status
public final class WatchHTTPEndpoint: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.openisland", category: "WatchHTTPEndpoint")
    private static let serviceType = "_openisland._tcp"
    static let pairingCodeLength = 4
    private static let pairingCodeExpiry: TimeInterval = 120 // 2 minutes
    /// Max failed /pair attempts before the endpoint locks out further attempts.
    private static let maxPairingFailures = 5
    /// How long a lockout lasts after the failure threshold is hit.
    private static let pairingLockoutDuration: TimeInterval = 60
    /// Maximum total size of a single buffered HTTP request.
    static let maxRequestByteCount = 1 * 1024 * 1024

    private let queue = DispatchQueue(label: "app.openisland.watch.http", qos: .userInitiated)

    // Pairing state
    private var currentPairingCode: String = ""
    private var pairingCodeGeneratedAt: Date = .distantPast
    private var validTokens: Set<String> = []
    // Brute-force protection: a 4-digit code is only 10k combinations, so an
    // unauthenticated attacker on the LAN could exhaust it without a limiter.
    private var pairingThrottle = PairingThrottle(
        maxFailures: WatchHTTPEndpoint.maxPairingFailures,
        lockoutDuration: WatchHTTPEndpoint.pairingLockoutDuration
    )

    // SSE connections
    private var sseConnections: [UUID: NWConnection] = [:]

    // Listener
    private var listener: NWListener?

    // Callbacks
    public var onResolution: WatchResolutionHandler?
    public var activeSessionCountProvider: WatchActiveSessionCountProvider?

    public init() {
        regeneratePairingCode()
    }

    // MARK: - Lifecycle

    public func start() {
        queue.async { [weak self] in
            self?.startListener()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for (id, connection) in self.sseConnections {
                connection.cancel()
                self.sseConnections.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Pairing Code

    /// Returns the current pairing code. Regenerates if expired.
    public func currentCode() -> String {
        queue.sync {
            if Date().timeIntervalSince(pairingCodeGeneratedAt) > Self.pairingCodeExpiry {
                regeneratePairingCodeUnsafe()
            }
            return currentPairingCode
        }
    }

    /// Force-regenerate pairing code (thread-safe).
    public func regeneratePairingCode() {
        queue.sync {
            regeneratePairingCodeUnsafe()
        }
    }

    /// Revoke all paired tokens, forcing re-pairing.
    public func revokeAllTokens() {
        queue.sync {
            validTokens.removeAll()
        }
    }

    // MARK: - SSE Push

    /// Push an SSE event to all authenticated, connected clients.
    public func pushEvent(_ event: WatchSSEEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            let payload = event.sseString()
            guard let data = payload.data(using: .utf8) else { return }
            for (id, connection) in self.sseConnections {
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        Self.logger.warning("SSE send failed for \(id): \(error.localizedDescription)")
                    }
                })
            }
        }
    }

    // MARK: - Private: Listener

    private func startListener() {
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params)

            // Bonjour advertising
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Mac",
                type: Self.serviceType
            )

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = self?.listener?.port {
                        Self.logger.info("WatchHTTPEndpoint listening on port \(port.rawValue)")
                    }
                case let .failed(error):
                    Self.logger.error("WatchHTTPEndpoint listener failed: \(error.localizedDescription)")
                    // Attempt restart after delay
                    self?.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.startListener()
                    }
                case .cancelled:
                    Self.logger.info("WatchHTTPEndpoint listener cancelled")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Self.logger.error("Failed to create NWListener: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection)
    }

    private func receiveHTTPRequest(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                Self.logger.debug("Connection receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let content {
                buffer.append(content)
            }

            // Cap the in-flight request so a slowloris/oversized client can't
            // grow memory without bound.
            guard buffer.count <= Self.maxRequestByteCount else {
                self.sendHTTPResponse(connection: connection, status: "413 Payload Too Large", body: #"{"error":"request too large"}"#)
                return
            }

            // Wait until we have the full headers, then until the full body
            // (per Content-Length) has arrived — a request can span multiple
            // TCP segments.
            switch Self.requestState(of: buffer) {
            case .incomplete:
                if isComplete {
                    // Peer closed before sending a complete request.
                    connection.cancel()
                } else {
                    self.receiveHTTPRequest(on: connection, accumulated: buffer)
                }
            case .complete:
                self.routeHTTPRequest(data: buffer, connection: connection)
            }
        }
    }

    enum RequestParseState: Equatable {
        case incomplete
        case complete
    }

    /// Parsed view of an HTTP request's head. `headers` keys preserve their
    /// original casing; `contentLength` is the parsed, validated body length
    /// (nil when absent), and `contentLengthInvalid` flags a present-but-garbage
    /// (negative / non-numeric / oversized) value so routing can reject it.
    struct RequestHead {
        var method: String
        var path: String
        var headers: [String: String]
        var contentLength: Int?
        var contentLengthInvalid: Bool
        /// Byte offset (from the buffer's start) at which the body begins.
        var bodyStartOffset: Int
    }

    private static let crlfcrlf = Data("\r\n\r\n".utf8)

    /// Single source of truth for HTTP framing: locates the header terminator,
    /// parses the request line + headers, and validates Content-Length. Returns
    /// nil while the header section is still incomplete. Both the completeness
    /// check and routing consume this so framing semantics live in one place.
    static func parseRequestHead(_ data: Data) -> RequestHead? {
        guard let headerEnd = data.range(of: crlfcrlf) else {
            return nil
        }

        let bodyStartOffset = data.distance(from: data.startIndex, to: headerEnd.upperBound)
        let headerData = data[data.startIndex..<headerEnd.lowerBound]

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            // Non-UTF8 headers: surface an empty head so routing rejects with a
            // 400 rather than buffering forever.
            return RequestHead(
                method: "",
                path: "",
                headers: [:],
                contentLength: nil,
                contentLengthInvalid: false,
                bodyStartOffset: bodyStartOffset
            )
        }

        let lines = headerString.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let requestParts = requestLine.split(separator: " ", maxSplits: 2)
        let method = requestParts.count > 0 ? String(requestParts[0]) : ""
        let path = requestParts.count > 1 ? String(requestParts[1]) : ""

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        var contentLength: Int?
        var contentLengthInvalid = false
        for (key, value) in headers where key.lowercased() == "content-length" {
            if let parsed = Int(value), parsed >= 0, parsed <= maxRequestByteCount {
                contentLength = parsed
            } else {
                contentLengthInvalid = true
            }
            break
        }

        return RequestHead(
            method: method,
            path: path,
            headers: headers,
            contentLength: contentLength,
            contentLengthInvalid: contentLengthInvalid,
            bodyStartOffset: bodyStartOffset
        )
    }

    /// Determines whether `buffer` contains a complete HTTP request: full header
    /// section (terminated by CRLFCRLF) plus a body matching Content-Length.
    static func requestState(of buffer: Data) -> RequestParseState {
        guard let head = parseRequestHead(buffer) else {
            return .incomplete
        }
        // A garbage Content-Length can never be satisfied by waiting; treat the
        // request as complete so routing can reject it with a 400.
        if head.contentLengthInvalid {
            return .complete
        }
        let bodyLength = buffer.count - head.bodyStartOffset
        return bodyLength >= (head.contentLength ?? 0) ? .complete : .incomplete
    }

    // MARK: - Private: HTTP Routing

    private func routeHTTPRequest(data: Data, connection: NWConnection) {
        guard let head = Self.parseRequestHead(data), !head.method.isEmpty else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid request"}"#)
            return
        }

        if head.contentLengthInvalid {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid content-length"}"#)
            return
        }

        let bodyStart = data.index(data.startIndex, offsetBy: head.bodyStartOffset)
        let bodyData = data[bodyStart...]
        let body = bodyData.isEmpty ? nil : String(data: Data(bodyData), encoding: .utf8)

        switch (head.method, head.path) {
        case ("POST", "/pair"):
            handlePair(body: body, connection: connection)

        case ("GET", "/events"):
            handleEventsSSE(headers: head.headers, connection: connection)

        case ("POST", "/resolution"):
            handleResolution(body: body, headers: head.headers, connection: connection)

        case ("GET", "/status"):
            handleStatus(headers: head.headers, connection: connection)

        default:
            sendHTTPResponse(connection: connection, status: "404 Not Found", body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - Private: Endpoint Handlers

    private func handlePair(body: String?, connection: NWConnection) {
        // Reject while locked out from too many failed attempts.
        if pairingThrottle.isLockedOut(now: Date()) {
            sendHTTPResponse(connection: connection, status: "429 Too Many Requests", body: #"{"error":"too many attempts"}"#)
            return
        }

        guard let body, let bodyData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(WatchPairRequest.self, from: bodyData) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid body"}"#)
            return
        }

        // Check if pairing code expired
        if Date().timeIntervalSince(pairingCodeGeneratedAt) > Self.pairingCodeExpiry {
            regeneratePairingCodeUnsafe()
            sendHTTPResponse(connection: connection, status: "410 Gone", body: #"{"error":"pairing code expired"}"#)
            return
        }

        guard request.code == currentPairingCode else {
            pairingThrottle.registerFailure(now: Date())
            sendHTTPResponse(connection: connection, status: "403 Forbidden", body: #"{"error":"invalid pairing code"}"#)
            return
        }

        // Success — clear the brute-force counter.
        pairingThrottle.reset()

        // Generate token
        let token = UUID().uuidString
        validTokens.insert(token)

        // Regenerate pairing code after successful pair
        regeneratePairingCodeUnsafe()

        let response = WatchPairResponse(token: token)
        if let responseData = try? JSONEncoder().encode(response),
           let responseString = String(data: responseData, encoding: .utf8) {
            sendHTTPResponse(connection: connection, status: "200 OK", body: responseString)
        }
    }

    /// Brute-force throttle for the pairing endpoint. Pure value type with
    /// injectable time so the lockout state machine is unit-testable.
    ///
    /// The lockout is intentionally global (not per-peer): this is a local-first
    /// app on a trusted LAN, so a single counter is enough to defeat brute-force
    /// of the 4-digit code. It deliberately does NOT rotate the code on lockout —
    /// the code already rotates on expiry and on successful pairing, and rotating
    /// here would let any LAN peer invalidate the legitimate user's displayed
    /// code mid-pairing. After the lockout window passes the same code still
    /// works for the real user.
    struct PairingThrottle {
        let maxFailures: Int
        let lockoutDuration: TimeInterval
        private(set) var failureCount = 0
        private(set) var lockedOutUntil: Date = .distantPast

        func isLockedOut(now: Date) -> Bool {
            now < lockedOutUntil
        }

        mutating func registerFailure(now: Date) {
            failureCount += 1
            if failureCount >= maxFailures {
                lockedOutUntil = now.addingTimeInterval(lockoutDuration)
                failureCount = 0
            }
        }

        mutating func reset() {
            failureCount = 0
            lockedOutUntil = .distantPast
        }
    }

    private func handleEventsSSE(headers: [String: String], connection: NWConnection) {
        guard authenticateRequest(headers: headers) else {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }

        // Send SSE headers and keep connection open
        let sseHeaders = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        \r

        """

        guard let headerData = sseHeaders.data(using: .utf8) else { return }

        let connectionID = UUID()
        sseConnections[connectionID] = connection

        let queue = self.queue
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if let error {
                Self.logger.warning("Failed to send SSE headers: \(error.localizedDescription)")
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
                connection.cancel()
                return
            }

            // Send initial keepalive comment
            guard let keepalive = ": connected\n\n".data(using: .utf8) else { return }
            connection.send(content: keepalive, completion: .contentProcessed { _ in })
        })

        // Monitor for disconnect
        connection.viabilityUpdateHandler = { [weak self] isViable in
            if !isViable {
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
            }
        }

        // Detect connection close
        monitorSSEConnection(connectionID: connectionID, connection: connection)
    }

    private func monitorSSEConnection(connectionID: UUID, connection: NWConnection) {
        let queue = self.queue
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
                connection.cancel()
            } else {
                self?.monitorSSEConnection(connectionID: connectionID, connection: connection)
            }
        }
    }

    private func handleResolution(body: String?, headers: [String: String], connection: NWConnection) {
        guard authenticateRequest(headers: headers) else {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }

        guard let body, let bodyData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(WatchResolutionRequest.self, from: bodyData) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid body"}"#)
            return
        }

        onResolution?(request)
        sendHTTPResponse(connection: connection, status: "200 OK", body: #"{"status":"accepted"}"#)
    }

    private func handleStatus(headers: [String: String], connection: NWConnection) {
        guard authenticateRequest(headers: headers) else {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }

        let response = WatchStatusResponse(
            connected: !sseConnections.isEmpty,
            activeSessionCount: activeSessionCountProvider?() ?? 0
        )

        if let responseData = try? JSONEncoder().encode(response),
           let responseString = String(data: responseData, encoding: .utf8) {
            sendHTTPResponse(connection: connection, status: "200 OK", body: responseString)
        }
    }

    // MARK: - Auth

    /// Constant-time string equality — visits every byte and does not branch on
    /// content, so verification time does not reveal where a mismatch occurred.
    /// STUB (Red): filled in during Green.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        false
    }

    /// Extract the bearer token from HTTP headers, or nil if absent/malformed.
    /// STUB (Red): filled in during Green.
    static func bearerToken(from headers: [String: String]) -> String? {
        nil
    }

    /// Whether `token` is one of the currently valid tokens, compared in
    /// constant time with no early-out across the set (timing side-channel).
    /// STUB (Red): filled in during Green.
    static func isAuthorizedToken(_ token: String, among validTokens: Set<String>) -> Bool {
        false
    }

    private func authenticateRequest(headers: [String: String]) -> Bool {
        guard let token = Self.bearerToken(from: headers) else { return false }
        return Self.isAuthorizedToken(token, among: validTokens)
    }

    // MARK: - Private: HTTP Helpers

    private func sendHTTPResponse(connection: NWConnection, status: String, body: String, contentType: String = "application/json") {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        guard let data = response.data(using: .utf8) else { return }
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Private: Pairing Code Generation

    /// Generate a numeric pairing code of the given length (digits only).
    /// Pure so the keyspace/charset is unit-testable.
    /// STUB (Red): filled in during Green.
    static func makePairingCode(length: Int) -> String {
        ""
    }

    /// Must be called on `queue`.
    private func regeneratePairingCodeUnsafe() {
        currentPairingCode = Self.makePairingCode(length: Self.pairingCodeLength)
        pairingCodeGeneratedAt = Date()
        Self.logger.info("New pairing code generated")
    }
}
