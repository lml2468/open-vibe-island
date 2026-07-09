import Foundation
import OpenIslandCore

/// A Ghostty terminal surface discovered via AppleScript. Shared by the terminal
/// probe/resolver pair (moved verbatim from their byte-identical nested copies).
struct GhosttyTerminalSnapshot: Sendable {
    var sessionID: String
    var workingDirectory: String
    var title: String
}

/// A Terminal.app tab discovered via AppleScript. Shared by the terminal
/// probe/resolver pair (moved verbatim from their byte-identical nested copies).
struct TerminalTabSnapshot: Sendable {
    var tty: String
    var customTitle: String
}

/// Shared helpers for the terminal AppleScript probe/resolver pair
/// (`TerminalJumpTargetResolver` and `TerminalSessionAttachmentProbe`), extracted
/// from their byte-identical private copies. Grows as later cluster-A slices land.
enum TerminalProbeSupport {
    /// Normalize a terminal app name for comparison: trim surrounding whitespace
    /// and lowercase.
    static func normalizedTerminalName(for value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Trimmed value, or nil if nil / whitespace-only.
    static func nonEmptyValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Reconcile a session's jump target against a discovered Terminal.app tab.
    /// Returns the corrected target if any field changed, else nil (and nil when
    /// the session has no jump target).
    static func correctedTerminalJumpTarget(
        for session: AgentSession,
        snapshot: TerminalTabSnapshot
    ) -> JumpTarget? {
        guard var jumpTarget = session.jumpTarget else {
            return nil
        }

        var changed = false

        if normalizedTerminalName(for: jumpTarget.terminalApp) != "terminal" {
            jumpTarget.terminalApp = "Terminal"
            changed = true
        }

        if nonEmptyValue(jumpTarget.terminalTTY) != snapshot.tty {
            jumpTarget.terminalTTY = snapshot.tty
            changed = true
        }

        if let title = nonEmptyValue(snapshot.customTitle),
           title != jumpTarget.paneTitle {
            jumpTarget.paneTitle = title
            changed = true
        }

        return changed ? jumpTarget : nil
    }

    /// Run an AppleScript via `/usr/bin/osascript`, bounded by `timeout`. Shared
    /// default behind the terminal probes' injected `appleScriptRunner` seam.
    /// Throws an `NSError` in `errorDomain` (code 408 on timeout, else the
    /// process's exit status) on failure; returns the trimmed stdout on success.
    static func runOSAScript(
        _ script: String,
        timeout: TimeInterval,
        errorDomain: String
    ) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        let completionGroup = DispatchGroup()
        completionGroup.enter()
        task.terminationHandler = { _ in
            completionGroup.leave()
        }

        try task.run()
        let waitResult = completionGroup.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            task.terminate()
            _ = completionGroup.wait(timeout: .now() + 0.2)
            throw NSError(domain: errorDomain, code: 408, userInfo: [
                NSLocalizedDescriptionKey: "AppleScript probe timed out.",
            ])
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard task.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: errorDomain, code: Int(task.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: stderr.isEmpty ? "AppleScript probe failed." : stderr,
            ])
        }

        return output
    }

    /// AppleScript that enumerates open Ghostty terminals, emitting one record per
    /// terminal (`id`, `working directory`, `name`) delimited by ASCII field (31)
    /// and record (30) separators. Shared verbatim by the probe and the resolver;
    /// each parses the output with its own (optional vs throwing) wrapper.
    static let ghosttyEnumerationScript = """
    set fieldSeparator to ASCII character 31
    set recordSeparator to ASCII character 30
    tell application "Ghostty"
        if not (it is running) then return ""
        set outputLines to {}
        repeat with aTerminal in terminals
            set terminalID to ""
            set terminalDirectory to ""
            set terminalTitle to ""
            try
                set terminalID to (id of aTerminal as text)
            end try
            try
                set terminalDirectory to (working directory of aTerminal as text)
            end try
            try
                set terminalTitle to (name of aTerminal as text)
            end try
            set end of outputLines to terminalID & fieldSeparator & terminalDirectory & fieldSeparator & terminalTitle
        end repeat
        set AppleScript's text item delimiters to recordSeparator
        set joinedOutput to outputLines as string
        set AppleScript's text item delimiters to ""
        return joinedOutput
    end tell
    """

    /// AppleScript that enumerates open Terminal.app tabs, emitting one record per
    /// tab (`tty`, `custom title`) delimited by ASCII field (31) and record (30)
    /// separators. Shared verbatim by the probe and the resolver.
    static let terminalEnumerationScript = """
    set fieldSeparator to ASCII character 31
    set recordSeparator to ASCII character 30
    tell application "Terminal"
        if not (it is running) then return ""
        set outputLines to {}
        repeat with aWindow in windows
            repeat with aTab in tabs of aWindow
                set tabTTY to ""
                set tabTitle to ""
                try
                    set tabTTY to (tty of aTab as text)
                end try
                try
                    set tabTitle to (custom title of aTab as text)
                end try
                set end of outputLines to tabTTY & fieldSeparator & tabTitle
            end repeat
        end repeat
        set AppleScript's text item delimiters to recordSeparator
        set joinedOutput to outputLines as string
        set AppleScript's text item delimiters to ""
        return joinedOutput
    end tell
    """
}
