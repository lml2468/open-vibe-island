import Foundation

/// Extracts complete newline-terminated lines from a streaming byte buffer,
/// leaving any unterminated trailing bytes in `buffer` for the next read.
///
/// This is the hot path for tailing large JSONL transcripts. It scans the buffer
/// **once** and drops the consumed prefix a **single** time — the previous
/// per-line `Data.removeSubrange(...idx)` loop was O(n^2) because front-removal on
/// `Data` copies the remaining bytes on every iteration.
///
/// Behavior (kept identical to the loops it replaced):
/// - splits on `\n`; the newline is not included in a returned line,
/// - empty lines (a bare `\n`, or `\n\n`) are skipped,
/// - a trailing partial line (no final `\n`) is left in `buffer`,
/// - lines are decoded as UTF-8 (lossy-free `String(decoding:as:)`).
func extractNDJSONLines(from buffer: inout Data) -> [String] {
    let newline = UInt8(ascii: "\n")
    guard !buffer.isEmpty else { return [] }

    var lines: [String] = []
    // `Data` slices preserve the parent's index base, so iterate over the
    // element offsets explicitly rather than assuming a 0-based start.
    var consumedUpToOffset = 0   // offset (from the buffer's start) past the last '\n'
    var lineStartOffset = 0

    for (offset, byte) in buffer.enumerated() {
        guard byte == newline else { continue }

        if offset > lineStartOffset {
            let lineStart = buffer.index(buffer.startIndex, offsetBy: lineStartOffset)
            let lineEnd = buffer.index(buffer.startIndex, offsetBy: offset)
            lines.append(String(decoding: buffer[lineStart..<lineEnd], as: UTF8.self))
        }
        // else: empty line (offset == lineStartOffset) — skip, matching old behavior.

        lineStartOffset = offset + 1
        consumedUpToOffset = offset + 1
    }

    if consumedUpToOffset > 0 {
        if consumedUpToOffset >= buffer.count {
            buffer.removeAll(keepingCapacity: false)
        } else {
            let dropEnd = buffer.index(buffer.startIndex, offsetBy: consumedUpToOffset)
            buffer.removeSubrange(buffer.startIndex..<dropEnd)
        }
    }

    return lines
}
