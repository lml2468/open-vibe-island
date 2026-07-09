import Testing
@testable import OpenIslandApp

/// Shared terminal-name normalization used by the AppleScript probe/resolver
/// (slice `dedup-terminal-normalize`, discovery finding #9 cluster A).
struct TerminalProbeSupportTests {
    @Test
    func nilStaysNil() {
        #expect(TerminalProbeSupport.normalizedTerminalName(for: nil) == nil)
    }

    @Test
    func lowercasesValue() {
        #expect(TerminalProbeSupport.normalizedTerminalName(for: "Ghostty") == "ghostty")
    }

    @Test
    func trimsSurroundingWhitespaceAndNewlines() {
        #expect(TerminalProbeSupport.normalizedTerminalName(for: "  Ghostty \n") == "ghostty")
    }

    @Test
    func whitespaceOnlyBecomesEmpty() {
        #expect(TerminalProbeSupport.normalizedTerminalName(for: "   ") == "")
    }

    @Test
    func alreadyNormalizedIsUnchanged() {
        #expect(TerminalProbeSupport.normalizedTerminalName(for: "iterm") == "iterm")
    }
}
