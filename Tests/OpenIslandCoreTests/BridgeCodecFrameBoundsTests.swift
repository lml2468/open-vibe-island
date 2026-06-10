import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeCodecFrameBoundsTests {
    @Test
    func oversizedUnterminatedFrameThrows() {
        // A peer that streams bytes without a newline must not grow the buffer
        // without bound — once the unterminated remainder exceeds the cap we
        // reject the connection rather than accumulating toward OOM.
        var buffer = Data(repeating: 0x41, count: BridgeCodec.maxFrameByteCount + 1)
        #expect(throws: BridgeTransportError.self) {
            _ = try BridgeCodec.decodeLines(from: &buffer)
        }
    }

    @Test
    func smallPartialFrameIsRetainedWithoutThrowing() throws {
        // A normal partial read (no newline yet, well under the cap) is buffered
        // and returns no messages — the bytes are kept for the next read.
        var buffer = Data(repeating: 0x41, count: 128)
        let messages = try BridgeCodec.decodeLines(from: &buffer)
        #expect(messages.isEmpty)
        #expect(buffer.count == 128)
    }

    @Test
    func completeFrameDecodes() throws {
        var buffer = try BridgeCodec.encodeLine(.command(.registerClient(role: .observer)))
        let messages = try BridgeCodec.decodeLines(from: &buffer)
        #expect(messages.count == 1)
        #expect(buffer.isEmpty)
    }
}
