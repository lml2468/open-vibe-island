import Foundation
import Testing
@testable import OpenIslandApp

/// Behavioral tests for the shared osascript runner (slice
/// `dedup-terminal-runapplescript`, discovery finding #9 cluster A). This is the
/// deduped default behind the terminal probes' injected `appleScriptRunner` seam.
struct TerminalProbeRunOSAScriptTests {
    @Test
    func returnsTrimmedOutputOfATrivialScript() throws {
        let output = try TerminalProbeSupport.runOSAScript(
            "return \"open-island\"",
            timeout: 5,
            errorDomain: "TestDomain"
        )
        #expect(output == "open-island")
    }

    @Test
    func throwsWithGivenDomainAndCodeOnTimeout() {
        let start = Date()
        do {
            _ = try TerminalProbeSupport.runOSAScript(
                "delay 5\nreturn \"late\"",
                timeout: 0.3,
                errorDomain: "TimeoutDomain"
            )
            #expect(Bool(false), "expected a timeout error, got a value")
        } catch let error as NSError {
            let elapsed = Date().timeIntervalSince(start)
            #expect(error.domain == "TimeoutDomain")
            #expect(error.code == 408)
            #expect(elapsed < 3.0, "must return near the timeout, not after the full 5s delay")
        } catch {
            #expect(Bool(false), "expected an NSError, got \(error)")
        }
    }

    @Test
    func throwsWithGivenDomainOnScriptError() {
        // A syntactically invalid script makes osascript exit non-zero.
        do {
            _ = try TerminalProbeSupport.runOSAScript(
                "this is not valid applescript @@@",
                timeout: 5,
                errorDomain: "ErrDomain"
            )
            #expect(Bool(false), "expected a script error, got a value")
        } catch let error as NSError {
            #expect(error.domain == "ErrDomain")
            #expect(error.code != 0)
        } catch {
            #expect(Bool(false), "expected an NSError, got \(error)")
        }
    }
}
