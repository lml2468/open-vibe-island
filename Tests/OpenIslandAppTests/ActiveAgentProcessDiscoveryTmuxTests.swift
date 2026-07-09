import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Per-sweep tmux query memoization (slice `perf-tmux-memoize`, discovery #2).
/// The global `tmux list-panes -a` / `list-clients` queries must run at most once
/// per `discover()` sweep regardless of how many tmux-attached agents there are.
struct ActiveAgentProcessDiscoveryTmuxTests {

    /// Reference box so the injected @Sendable commandRunner can count calls.
    private final class CommandCounter: @unchecked Sendable {
        var listPanes = 0
        var listClients = 0
    }

    /// Fake `ps` with two Claude agents (ttys001/ttys002) whose parent chain is a
    /// shell under the tmux-server (no recognized terminal → tmux resolution
    /// fires), plus a tmux client shell (ttys000) under Ghostty.
    private func tmuxFixtureRunner(counter: CommandCounter) -> ActiveAgentProcessDiscovery.CommandRunner {
        { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  101 501 ttys001 /Users/test/.local/bin/claude --resume 11111111-1111-1111-1111-111111111111
                  102 502 ttys002 /Users/test/.local/bin/claude --resume 22222222-2222-2222-2222-222222222222
                  501 900 ttys001 -/opt/homebrew/bin/fish
                  502 900 ttys002 -/opt/homebrew/bin/fish
                  900 1 ?? tmux new-session -s work
                  700 800 ttys000 -/opt/homebrew/bin/fish
                  800 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
                """
            }

            if executablePath == "/usr/sbin/lsof" {
                // No cwd/transcript needed — the --resume flag supplies sessionID.
                return ""
            }

            if executablePath == "/usr/bin/which" {
                return "/usr/bin/tmux\n"
            }

            if arguments.contains("list-panes") {
                counter.listPanes += 1
                return """
                /dev/ttys001\twork:0.0
                /dev/ttys002\twork:0.1
                """
            }

            if arguments.contains("list-clients") {
                counter.listClients += 1
                return "/dev/ttys000\n"
            }

            return nil
        }
    }

    // A1: N tmux-attached agents => at most one list-panes and one list-clients.
    @Test
    func tmuxQueriesRunAtMostOncePerSweep() {
        let counter = CommandCounter()
        let discovery = ActiveAgentProcessDiscovery(commandRunner: tmuxFixtureRunner(counter: counter))

        _ = discovery.discover()

        #expect(counter.listPanes <= 1)
        #expect(counter.listClients <= 1)
    }

    // A2: each agent still gets its own correct tmuxTarget + shared host/socket.
    @Test
    func tmuxResolutionPreservesPerAgentTargets() {
        let counter = CommandCounter()
        let discovery = ActiveAgentProcessDiscovery(commandRunner: tmuxFixtureRunner(counter: counter))

        let snapshots = discovery.discover()

        let agent1 = snapshots.first { $0.terminalTTY == "/dev/ttys001" }
        let agent2 = snapshots.first { $0.terminalTTY == "/dev/ttys002" }
        #expect(agent1?.tmuxTarget == "work:0.0")
        #expect(agent2?.tmuxTarget == "work:0.1")
        // Host terminal is the shared tmux client's terminal for both.
        #expect(agent1?.terminalApp == "Ghostty")
        #expect(agent2?.terminalApp == "Ghostty")
    }

    // A3: a sweep with no tmux-attached agents issues zero tmux subprocesses.
    @Test
    func noTmuxSweepIssuesNoTmuxQueries() {
        let counter = CommandCounter()
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                // A single Claude agent hosted directly by Ghostty (no tmux).
                return """
                  101 501 ttys001 /Users/test/.local/bin/claude --resume 33333333-3333-3333-3333-333333333333
                  501 900 ttys001 -/opt/homebrew/bin/fish
                  900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
                """
            }
            if executablePath == "/usr/sbin/lsof" { return "" }
            if arguments.contains("list-panes") { counter.listPanes += 1; return "" }
            if arguments.contains("list-clients") { counter.listClients += 1; return "" }
            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.contains { $0.terminalApp == "Ghostty" && $0.terminalTTY == "/dev/ttys001" })
        #expect(counter.listPanes == 0)
        #expect(counter.listClients == 0)
    }
}
