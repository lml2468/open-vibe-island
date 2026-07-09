import Testing
@testable import OpenIslandCore

/// POSIX single-quote shell escaping shared by the hook installers
/// (slice `dedup-shellquote`, discovery finding #9 cluster C).
struct ShellQuotingTests {
    @Test
    func quotesEmptyStringAsEmptyQuotes() {
        #expect(ShellQuoting.quote("") == "''")
    }

    @Test
    func wrapsPlainStringInSingleQuotes() {
        #expect(ShellQuoting.quote("abc") == "'abc'")
    }

    @Test
    func wrapsPathWithSpaces() {
        #expect(ShellQuoting.quote("/a b/c") == "'/a b/c'")
    }

    @Test
    func escapesEmbeddedSingleQuoteWithPosixIdiom() {
        // a'b -> 'a'\''b'
        #expect(ShellQuoting.quote("a'b") == "'a'\\''b'")
    }

    @Test
    func escapesMultipleSingleQuotes() {
        // '' -> ''\'''\'''  (open-quote + two escaped quotes + close-quote)
        #expect(ShellQuoting.quote("''") == "''\\'''\\'''")
    }
}
