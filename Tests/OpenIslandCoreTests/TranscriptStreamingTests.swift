import Foundation
import Testing
@testable import OpenIslandCore

/// Covers the perf-battery slice helpers (arch-quality-audit #13, #15):
/// linear NDJSON line extraction (behavior-identical to the old O(n^2) loops)
/// and tolerant ISO-8601 timestamp parsing.
struct TranscriptStreamingTests {

    // MARK: - #15 line extraction

    private func extract(_ s: String) -> (lines: [String], residual: String) {
        var buffer = Data(s.utf8)
        let lines = extractNDJSONLines(from: &buffer)
        return (lines, String(decoding: buffer, as: UTF8.self))
    }

    @Test
    func extractsMultipleCompleteLinesAndClearsBuffer() {
        let (lines, residual) = extract("a\nbb\nccc\n")
        #expect(lines == ["a", "bb", "ccc"])
        #expect(residual.isEmpty)
    }

    @Test
    func leavesTrailingPartialLineInBuffer() {
        let (lines, residual) = extract("a\nbb\nccc")
        #expect(lines == ["a", "bb"])
        #expect(residual == "ccc")
    }

    @Test
    func skipsEmptyLines() {
        let (lines, residual) = extract("a\n\n\nb\n")
        #expect(lines == ["a", "b"])
        #expect(residual.isEmpty)
    }

    @Test
    func emptyBufferYieldsNothing() {
        let (lines, residual) = extract("")
        #expect(lines.isEmpty)
        #expect(residual.isEmpty)
    }

    @Test
    func leadingNewlineIsSkippedResidualPreserved() {
        let (lines, residual) = extract("\npartial")
        #expect(lines.isEmpty)
        #expect(residual == "partial")
    }

    @Test
    func matchesOldLoopAcrossChunkedAppend() {
        // Feed bytes in small chunks (as streaming reads do) and confirm the
        // concatenated line output equals a single-shot parse.
        let payload = "line-one\nline-two\nline-three\npartial-tail"
        var chunked = Data()
        var collected: [String] = []
        for byte in payload.utf8 {
            chunked.append(byte)
            collected.append(contentsOf: extractNDJSONLines(from: &chunked))
        }
        #expect(collected == ["line-one", "line-two", "line-three"])
        #expect(String(decoding: chunked, as: UTF8.self) == "partial-tail")
    }

    // MARK: - #13 timestamp parsing

    @Test
    func parsesFractionalSecondTimestamp() {
        let date = TranscriptTimestamp.parse("2026-04-02T04:03:44.500Z")
        #expect(date == Date(timeIntervalSince1970: 1_775_102_624.5))
    }

    @Test
    func parsesWholeSecondTimestamp() {
        let date = TranscriptTimestamp.parse("2026-04-02T04:03:44Z")
        #expect(date == Date(timeIntervalSince1970: 1_775_102_624))
    }

    @Test
    func returnsNilForMissingOrGarbageTimestamp() {
        #expect(TranscriptTimestamp.parse(nil) == nil)
        #expect(TranscriptTimestamp.parse("") == nil)
        #expect(TranscriptTimestamp.parse("not-a-date") == nil)
    }
}
