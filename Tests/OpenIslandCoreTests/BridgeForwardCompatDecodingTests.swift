import Foundation
import Testing
@testable import OpenIslandCore

/// Covers forward-compatible NDJSON decoding (brief `bridge-security`, A4/A5):
/// an envelope, event, command, or response whose discriminator is unknown
/// (emitted by a newer peer) must be skipped rather than tearing down the
/// stream, while all known types still round-trip.
struct BridgeForwardCompatDecodingTests {
    private func line(_ json: String) -> Data {
        Data((json + "\n").utf8)
    }

    @Test
    func unknownEnvelopeTypeIsSkippedNotFatal() throws {
        // A frame with a wholly unknown envelope type is dropped; a valid frame
        // in the same buffer still decodes.
        var buffer = line(#"{"type":"telemetry","telemetry":{"x":1}}"#)
        buffer.append(try BridgeCodec.encodeLine(.command(.registerClient(role: .observer))))

        let messages = try BridgeCodec.decodeLines(from: &buffer)
        #expect(messages.count == 1)
        if case .command(.registerClient) = messages[0] {} else {
            Issue.record("expected the known registerClient frame to survive")
        }
        #expect(buffer.isEmpty)
    }

    @Test
    func unknownEventTypeIsSkippedNotFatal() throws {
        var buffer = line(#"{"type":"event","event":{"type":"warpDriveEngaged","warpDriveEngaged":{}}}"#)
        let messages = try BridgeCodec.decodeLines(from: &buffer)
        #expect(messages.isEmpty)
        #expect(buffer.isEmpty)
    }

    @Test
    func unknownCommandTypeIsSkippedNotFatal() throws {
        var buffer = line(#"{"type":"command","command":{"type":"selfDestruct"}}"#)
        let messages = try BridgeCodec.decodeLines(from: &buffer)
        #expect(messages.isEmpty)
        #expect(buffer.isEmpty)
    }

    @Test
    func genuinelyMalformedJSONStillThrows() {
        // Forward compat must not swallow real corruption: a frame that is not
        // valid JSON at all is still a hard error.
        var buffer = line("{ this is not json")
        #expect(throws: BridgeTransportError.self) {
            _ = try BridgeCodec.decodeLines(from: &buffer)
        }
    }

    @Test
    func allKnownEventTypesRoundTrip() throws {
        // Every event this app knows must survive encode → decode unchanged, so
        // the forward-compat guard did not regress the known path.
        for event in Self.allKnownEvents {
            var buffer = try BridgeCodec.encodeLine(.event(event))
            let messages = try BridgeCodec.decodeLines(from: &buffer)
            #expect(messages.count == 1)
            guard case let .event(decoded) = messages.first else {
                Issue.record("expected an event envelope for \(event)")
                continue
            }
            #expect(decoded == event)
        }
    }

    private static let ts = Date(timeIntervalSince1970: 1_700_000_000)

    private static var allKnownEvents: [AgentEvent] {
        [
            .sessionStarted(.init(sessionID: "s", title: "t", tool: .claudeCode, initialPhase: .running, summary: "sum", timestamp: ts)),
            .activityUpdated(.init(sessionID: "s", summary: "sum", phase: .running, timestamp: ts)),
            .permissionRequested(.init(
                sessionID: "s",
                request: PermissionRequest(title: "t", summary: "sum", affectedPath: "/tmp/x"),
                timestamp: ts
            )),
            .questionAsked(.init(
                sessionID: "s",
                prompt: QuestionPrompt(title: "q", options: ["a", "b"]),
                timestamp: ts
            )),
            .sessionCompleted(.init(sessionID: "s", summary: "done", timestamp: ts)),
            .jumpTargetUpdated(.init(
                sessionID: "s",
                jumpTarget: JumpTarget(terminalApp: "Terminal", workspaceName: "w", paneTitle: "p"),
                timestamp: ts
            )),
            .sessionMetadataUpdated(.init(sessionID: "s", codexMetadata: CodexSessionMetadata(initialUserPrompt: "hi"), timestamp: ts)),
            .claudeSessionMetadataUpdated(.init(sessionID: "s", claudeMetadata: ClaudeSessionMetadata(), timestamp: ts)),
            .geminiSessionMetadataUpdated(.init(sessionID: "s", geminiMetadata: GeminiSessionMetadata(), timestamp: ts)),
            .openCodeSessionMetadataUpdated(.init(sessionID: "s", openCodeMetadata: OpenCodeSessionMetadata(), timestamp: ts)),
            .cursorSessionMetadataUpdated(.init(sessionID: "s", cursorMetadata: CursorSessionMetadata(), timestamp: ts)),
            .actionableStateResolved(.init(sessionID: "s", summary: "ok", timestamp: ts)),
        ]
    }
}
