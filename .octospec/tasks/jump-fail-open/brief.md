---
type: Task
title: "Task: jump-fail-open"
description: Terminal jump honors fail-open on Automation denial and bounds every subprocess with a timeout; AX injection checks trust first
tags: ["correctness", "jump", "fail-open", "ax", "timeout"]
timestamp: 2026-07-08T11:34:19Z
# --- octospec extension fields ---
slug: jump-fail-open
upstream: arch-quality-audit-r2 (discovery findings #5, #14)
source: self
revision: 1
approvals: []
---

# Task: jump-fail-open

> Second slice of the `arch-quality-audit-r2` discovery. Makes the terminal
> jump-back path — the app's headline feature — degrade gracefully instead of
> hard-failing or hanging. Independent branch off `origin/main` (no chain with the
> watch-auth PR).

## Goal

Fix three joined correctness bugs on the jump / AX path (discovery #5 + #14):

1. **Fail-open on Automation denial.** The AppleScript jumpers are invoked with
   `try` — `jumpToITermSession` (`TerminalJumpService.swift:352`),
   `jumpToGhosttyTerminal` (`:360`), `jumpToTerminalTab` (`:364`) — so when
   `osascript` exits non-zero because the user declined the Automation (Apple
   Events) prompt, `defaultAppleScriptRunner` throws `.appleScriptFailed` (`:1312`)
   and the throw unwinds `jump(to:)` **past** the `open -b` activation fallbacks
   at `:401-419`. The user who declined the prompt gets a hard error instead of
   the app simply being brought forward. These call sites (and the tmux-path
   equivalents at `:263-270`) must fall through to the existing activation
   fallback when the AppleScript step fails, exactly like the `Bool`-returning
   CLI/socket jumpers already do — **without** swallowing genuinely unexpected
   errors silently.

2. **Bound every jump subprocess with a timeout.** `defaultOpenAction` (`:1280`),
   `defaultAppleScriptRunner` (`:1293`), and `defaultProcessRunner` (`:1318`) use
   `waitUntilExit()` with **no deadline**; a hung `osascript`/`open`/`code`/`idea`
   blocks the caller forever and leaks a `Process`, and `Task.cancel()` can't
   interrupt a blocking wait. Add a bounded wait that terminates the process on
   deadline, reusing the in-repo probe precedent
   (`TerminalSessionAttachmentProbe.swift:1331-1341`: `DispatchGroup.wait(timeout:)`
   → `terminate()`).

3. **Gate AX injection on trust.** `KeystrokeInjector.sendCmdShiftRightBracket`
   (`KeystrokeInjector.swift:59`) drives Warp's menu via AppleScript with no
   `AXIsProcessTrusted()` / permission pre-check (there is none anywhere in
   `Sources/`), so on denial it logs and returns while the caller wastes its full
   `tabCount+2` cycle loop (each iteration `Thread.sleep(0.1)` + a SQLite read).
   Add an injectable trust check that short-circuits the injection (and lets the
   caller skip the wasted loop) when the process is not trusted.

## Background

- `TerminalJumpService` already has injectable seams — `openAction`,
  `appleScriptRunner`, `processRunner` (`:210-243`) — used throughout
  `Tests/OpenIslandAppTests/TerminalJumpServiceTests.swift` to drive jumps with
  fakes. Fail-open behavior (1) is testable by injecting a throwing
  `appleScriptRunner` and asserting the jump still returns an activation message
  via `openAction`.
- The timeout (2) belongs in the `default*` static runners (the production
  implementations of those seams). Its bound is testable with a real short-lived
  subprocess (e.g. `sleep`) asserting the call returns within a small budget and
  reports failure rather than hanging.
- `KeystrokeInjector` (3) is currently `DefaultKeystrokeInjector` with a hardcoded
  `NSAppleScript` path; it needs a small injected `isProcessTrusted: () -> Bool`
  seam (default `AXIsProcessTrusted`) to be unit-testable without real TCC state.
- Related rule to read at Implement: none is currently indexed for these files;
  this slice will promote one (`terminal-jump-resilience`) at Finish.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`TerminalJumpService.jump(to:)` dispatch + fallback tail** (`:334-421`) — the
  AppleScript call sites and the `open -b` / working-dir / Finder fallbacks that a
  denial must reach. `[jump] [fail-open]`
- **`TerminalJumpService.default{OpenAction,AppleScriptRunner,ProcessRunner}`**
  (`:1280-1332`) — the unbounded `waitUntilExit()` sites. `[timeout]`
- **AppleScript jumpers** `jumpToITermSession`/`jumpToGhosttyTerminal`/
  `jumpToTerminalTab` and their tmux-path calls (`:263-270,:352-366,:424-453`) —
  the `throws`-propagating helpers. `[jump]`
- **`KeystrokeInjector` / `DefaultKeystrokeInjector`** (`:10,:59-78`) and its
  caller `jumpToWarpPane` (`TerminalJumpService.swift:~1153-1211`) — the
  untrusted-AX wasted-loop path. `[ax]`
- **Existing behavior contract:** a *successful* jump must return the same message
  as today; only the denial/timeout/untrusted paths change. `[jump]`

## Out of scope
- **The giant bundle-id `switch` / no `TerminalJumper` protocol** (discovery #18)
  — a separate refactor slice; this slice touches only the denial/timeout/trust
  behavior, not the dispatch structure.
- **`jumpToWarpPane` `Thread.sleep` blocking** (discovery #1.4) and the hardcoded
  English Warp menu path / localization (#14 menu-path) — behavior of the loop
  body stays; only the trust pre-check that lets the caller *skip* the loop is in
  scope.
- **The duplicated AppleScript probe cluster** (discovery #9) — dedup slice.
- **`WarpSQLiteReader` `busy_timeout`**, cmux `/tmp` trust, PATH resolution
  (#25) — separate concerns.
- No change to jump *success* messages, `JumpTarget`, or the injected-seam
  signatures beyond adding the trust seam to `KeystrokeInjector`.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — AppleScript denial falls through to activation (iTerm/Ghostty/Terminal).**
  With a running target app and an `appleScriptRunner` that throws
  `TerminalJumpError.appleScriptFailed`, `jump(to:)` for each of
  `com.googlecode.iterm2`, `com.mitchellh.ghostty`, `com.apple.Terminal` does NOT
  rethrow; it invokes `openAction(["-b", <bundle>])` and returns a non-throwing
  activation result. *(Testable: inject throwing `appleScriptRunner` + recording
  `openAction`; assert no throw + `open -b` called. Fails first — currently
  rethrows.)*
- **A2 — a genuinely unexpected jump error is still surfaced, not swallowed.** A
  non-AppleScript failure path (e.g. `openAction` itself throwing on the final
  fallback) still propagates out of `jump(to:)`. *(Testable: inject `openAction`
  that throws; assert `jump` throws. Guards against "fixed fail-open by catching
  everything".)*
- **A3 — bounded runner terminates a hung subprocess and reports failure.** The
  production runner used for `open`/osascript/CLIs returns within a bounded time
  when the child does not exit, reporting failure (throw for the AppleScript/open
  runner, `false` for the process runner) rather than blocking indefinitely.
  *(Testable: run the real `default*` runner against a long `sleep` with a small
  timeout; assert it returns well under the sleep duration and signals failure.)*
- **A4 — AX injection is skipped when the process is not trusted.** With an
  injected `isProcessTrusted` returning `false`, `KeystrokeInjector`'s send path
  does not attempt the AppleScript keystroke and reports "not performed"; with
  `true` it proceeds. *(Testable: inject the trust seam + a recording script
  runner; assert no keystroke attempt when untrusted. Fails first — no trust
  seam.)*
- **A5 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
