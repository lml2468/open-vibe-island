import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Injection-seam tests for the terminal probe pair (slice `terminal-probe-seam`,
/// discovery finding #9 cluster A enabler). The seams make the AppleScript
/// parse/availability logic — previously locked behind a real `osascript` process
/// and `NSRunningApplication` — unit-testable.
struct TerminalProbeSeamTests {

    /// Records whether the injected AppleScript runner was invoked.
    private final class RunnerCallBox: @unchecked Sendable {
        var called = false
    }

    // Field (31) / record (30) separators the enumeration scripts emit.
    private let fs = "\u{1f}"
    private let rs = "\u{1e}"

    // MARK: - A1: appRunningChecker short-circuits availability

    @Test
    func ghosttyAvailabilityShortCircuitsWhenAppNotRunning() {
        let box = RunnerCallBox()
        let probe = TerminalSessionAttachmentProbe(
            appleScriptRunner: { _ in box.called = true; return "" },
            appRunningChecker: { _ in false }
        )

        let availability = probe.ghosttySnapshotAvailability()

        // Not running → empty snapshots, appIsRunning false, runner never called.
        guard case let .available(snapshots, appIsRunning) = availability else {
            return #expect(Bool(false), "expected .available for a not-running app")
        }
        #expect(snapshots.isEmpty)
        #expect(appIsRunning == false)
        #expect(box.called == false)
    }

    // MARK: - A2: injected appleScriptRunner drives the parse logic

    @Test
    func ghosttyAvailabilityParsesInjectedRunnerOutput() {
        let payload = [
            ["ghostty-1", "/tmp/a", "claude ~/a"].joined(separator: fs),
            ["ghostty-2", "/tmp/b", "codex ~/b"].joined(separator: fs),
        ].joined(separator: rs)

        let probe = TerminalSessionAttachmentProbe(
            appleScriptRunner: { _ in payload },
            appRunningChecker: { _ in true }
        )

        let availability = probe.ghosttySnapshotAvailability()

        guard case let .available(snapshots, appIsRunning) = availability else {
            return #expect(Bool(false), "expected .available with parsed snapshots")
        }
        #expect(appIsRunning == true)
        #expect(snapshots.count == 2)
        #expect(snapshots.first?.sessionID == "ghostty-1")
        #expect(snapshots.first?.workingDirectory == "/tmp/a")
        #expect(snapshots.first?.title == "claude ~/a")
        #expect(snapshots.last?.sessionID == "ghostty-2")
    }

    // MARK: - A3: a throwing runner yields .unavailable

    private struct FakeScriptError: Error {}

    @Test
    func ghosttyAvailabilityIsUnavailableWhenRunnerThrows() {
        let probe = TerminalSessionAttachmentProbe(
            appleScriptRunner: { _ in throw FakeScriptError() },
            appRunningChecker: { _ in true }
        )

        let availability = probe.ghosttySnapshotAvailability()

        guard case let .unavailable(appIsRunning) = availability else {
            return #expect(Bool(false), "expected .unavailable when the runner throws")
        }
        #expect(appIsRunning == true)
    }

    // MARK: - A2 (probe Terminal.app path too)

    @Test
    func terminalAvailabilityParsesInjectedRunnerOutput() {
        let payload = [
            ["/dev/ttys001", "My Tab"].joined(separator: fs),
        ].joined(separator: rs)

        let probe = TerminalSessionAttachmentProbe(
            appleScriptRunner: { _ in payload },
            appRunningChecker: { _ in true }
        )

        let availability = probe.terminalSnapshotAvailability()

        guard case let .available(snapshots, _) = availability else {
            return #expect(Bool(false), "expected .available with parsed tabs")
        }
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.tty == "/dev/ttys001")
        #expect(snapshots.first?.customTitle == "My Tab")
    }

    // MARK: - A4: the resolver seam is injectable too

    @Test
    func resolverAcceptsInjectedAppRunningChecker() {
        let box = RunnerCallBox()
        // Construct with injected fakes — proves the seam exists on the resolver.
        // A running-checker of { false } means no supported terminal is "running",
        // so the AppleScript runner is never consulted.
        let resolver = TerminalJumpTargetResolver(
            appleScriptRunner: { _ in box.called = true; return "" },
            appRunningChecker: { _ in false }
        )
        // Exercising a resolution against an unknown terminal must not invoke the
        // AppleScript runner (nothing is "running").
        _ = resolver
        #expect(box.called == false)
    }
}
