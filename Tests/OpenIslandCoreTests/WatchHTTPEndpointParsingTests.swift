import Foundation
import Testing
@testable import OpenIslandCore

struct WatchHTTPEndpointParsingTests {
    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    // MARK: - requestState

    @Test
    func headerSectionIncompleteIsIncomplete() {
        let buffer = data("POST /pair HTTP/1.1\r\nContent-Length: 10\r\n")
        #expect(WatchHTTPEndpoint.requestState(of: buffer) == .incomplete)
    }

    @Test
    func headersCompleteButBodyShortIsIncomplete() {
        let buffer = data("POST /pair HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort")
        #expect(WatchHTTPEndpoint.requestState(of: buffer) == .incomplete)
    }

    @Test
    func fullBodyIsComplete() {
        let buffer = data("POST /pair HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
        #expect(WatchHTTPEndpoint.requestState(of: buffer) == .complete)
    }

    @Test
    func noContentLengthWithHeaderTerminatorIsComplete() {
        let buffer = data("GET /status HTTP/1.1\r\nAuthorization: Bearer x\r\n\r\n")
        #expect(WatchHTTPEndpoint.requestState(of: buffer) == .complete)
    }

    @Test
    func negativeContentLengthIsTreatedAsCompleteSoRoutingCanReject() {
        // A garbage Content-Length can never be satisfied by waiting; mark
        // complete so routing returns a 400 rather than buffering forever.
        let buffer = data("POST /pair HTTP/1.1\r\nContent-Length: -1\r\n\r\n")
        #expect(WatchHTTPEndpoint.requestState(of: buffer) == .complete)
    }

    // MARK: - parseRequestHead

    @Test
    func parsesMethodPathAndHeaders() {
        let head = WatchHTTPEndpoint.parseRequestHead(
            data("POST /resolution HTTP/1.1\r\nContent-Length: 2\r\nX-Test: hi\r\n\r\n{}")
        )
        #expect(head?.method == "POST")
        #expect(head?.path == "/resolution")
        #expect(head?.headers["X-Test"] == "hi")
        #expect(head?.contentLength == 2)
        #expect(head?.contentLengthInvalid == false)
    }

    @Test
    func flagsNegativeContentLengthInvalid() {
        let head = WatchHTTPEndpoint.parseRequestHead(
            data("POST /pair HTTP/1.1\r\nContent-Length: -5\r\n\r\n")
        )
        #expect(head?.contentLengthInvalid == true)
        #expect(head?.contentLength == nil)
    }

    @Test
    func flagsNonNumericContentLengthInvalid() {
        let head = WatchHTTPEndpoint.parseRequestHead(
            data("POST /pair HTTP/1.1\r\nContent-Length: abc\r\n\r\n")
        )
        #expect(head?.contentLengthInvalid == true)
    }

    @Test
    func returnsNilWhileHeadersIncomplete() {
        #expect(WatchHTTPEndpoint.parseRequestHead(data("POST /pair HTTP/1.1\r\n")) == nil)
    }

    @Test
    func bodyOffsetAllowsBodyContainingBlankLine() {
        // A body that itself contains a blank line must not be truncated: the
        // body starts right after the first CRLFCRLF.
        let body = "line1\r\n\r\nline2"
        let raw = "POST /resolution HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let buffer = data(raw)
        let head = WatchHTTPEndpoint.parseRequestHead(buffer)
        #expect(head != nil)
        let bodyStart = buffer.index(buffer.startIndex, offsetBy: head!.bodyStartOffset)
        let extracted = String(data: Data(buffer[bodyStart...]), encoding: .utf8)
        #expect(extracted == body)
    }
}

struct PairingThrottleTests {
    @Test
    func locksOutAfterMaxFailures() {
        var throttle = WatchHTTPEndpoint.PairingThrottle(maxFailures: 5, lockoutDuration: 60)
        let now = Date(timeIntervalSince1970: 1_000)

        for _ in 0..<4 {
            throttle.registerFailure(now: now)
            #expect(throttle.isLockedOut(now: now) == false)
        }
        // 5th failure trips the lockout.
        throttle.registerFailure(now: now)
        #expect(throttle.isLockedOut(now: now) == true)
        // Still locked just before the window closes.
        #expect(throttle.isLockedOut(now: now.addingTimeInterval(59)) == true)
        // Unlocked after the window passes.
        #expect(throttle.isLockedOut(now: now.addingTimeInterval(61)) == false)
    }

    @Test
    func successResetsCounter() {
        var throttle = WatchHTTPEndpoint.PairingThrottle(maxFailures: 5, lockoutDuration: 60)
        let now = Date(timeIntervalSince1970: 2_000)

        for _ in 0..<4 { throttle.registerFailure(now: now) }
        throttle.reset()
        // After reset it should take a full new run of failures to lock out.
        for _ in 0..<4 {
            throttle.registerFailure(now: now)
            #expect(throttle.isLockedOut(now: now) == false)
        }
        throttle.registerFailure(now: now)
        #expect(throttle.isLockedOut(now: now) == true)
    }
}
