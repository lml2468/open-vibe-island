import Darwin
import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

/// Covers the bridge write-timeout hardening (brief `bridge-security`, A1/A5):
/// `writeAll` must not spin forever when a peer stops draining its receive
/// buffer — all server writes share one serial queue, so an unbounded write
/// wedges the entire bridge. On timeout it throws so the caller drops that peer.
struct BridgeWriteTimeoutTests {
    /// Create a connected AF_UNIX socket pair with both ends non-blocking.
    private func makeSocketPair() -> (Int32, Int32)? {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { return nil }
        try? makeSocketNonBlocking(fds[0])
        try? makeSocketNonBlocking(fds[1])
        try? disableSocketSigPipe(fds[0])
        return (fds[0], fds[1])
    }

    @Test
    func writeAllThrowsWhenPeerNeverDrains() throws {
        guard let (writeEnd, readEnd) = makeSocketPair() else {
            Issue.record("socketpair unavailable")
            return
        }
        defer { close(writeEnd); close(readEnd) }

        // Fill both the send buffer and the peer's unread receive buffer so the
        // next write cannot make progress and stays at EAGAIN.
        let filler = [UInt8](repeating: 0x41, count: 1 << 16)
        var guardCounter = 0
        while guardCounter < 100_000 {
            let n = filler.withUnsafeBytes { write(writeEnd, $0.baseAddress, $0.count) }
            if n == -1 { break } // EAGAIN — buffers are full
            guardCounter += 1
        }

        // With buffers full and the peer never reading, writeAll must give up at
        // the deadline rather than looping forever. The payload is far larger
        // than any plausible socket-buffer headroom left after the fill loop, so
        // the write is guaranteed to block on EAGAIN and hit the deadline (a
        // small payload could occasionally fit entirely into leftover headroom).
        let start = DispatchTime.now()
        #expect(throws: BridgeTransportError.self) {
            try writeAll(Data(repeating: 0x42, count: 8 << 20), to: writeEnd, timeout: 0.25)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        // Bounded: comfortably above the 0.25s deadline would indicate a spin.
        #expect(elapsed < 3.0)
    }

    @Test
    func writeAllSucceedsWhenPeerDrains() throws {
        guard let (writeEnd, readEnd) = makeSocketPair() else {
            Issue.record("socketpair unavailable")
            return
        }
        defer { close(writeEnd); close(readEnd) }

        let payload = Data(repeating: 0x37, count: 2048)
        // A reader that drains keeps the send buffer clear, so writeAll completes.
        let drain = DispatchQueue(label: "drain")
        drain.async {
            var buf = [UInt8](repeating: 0, count: 4096)
            var total = 0
            while total < payload.count {
                let n = read(readEnd, &buf, buf.count)
                if n > 0 { total += n } else if n == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    usleep(1_000)
                } else { break }
            }
        }

        try writeAll(payload, to: writeEnd, timeout: 2.0)
    }
}
