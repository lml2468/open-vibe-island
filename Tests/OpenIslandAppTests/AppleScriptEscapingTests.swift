import Testing
@testable import OpenIslandApp

/// AppleScript double-quote-string escaping shared by the jump/send paths
/// (slice `dedup-escape-applescript`, discovery finding #9 cluster C).
struct AppleScriptEscapingTests {
    @Test
    func nilBecomesEmptyString() {
        #expect(AppleScriptEscaping.escape(nil) == "")
    }

    @Test
    func plainStringPassesThrough() {
        #expect(AppleScriptEscaping.escape("abc") == "abc")
    }

    @Test
    func escapesBackslash() {
        #expect(AppleScriptEscaping.escape("a\\b") == "a\\\\b")
    }

    @Test
    func escapesDoubleQuote() {
        #expect(AppleScriptEscaping.escape("a\"b") == "a\\\"b")
    }

    @Test
    func escapesBackslashBeforeQuoteInOrder() {
        // Input  \"  ->  backslash escaped first (\\), then quote (\") => \\\"
        #expect(AppleScriptEscaping.escape("\\\"") == "\\\\\\\"")
    }
}
