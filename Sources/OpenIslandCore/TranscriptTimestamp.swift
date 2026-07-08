import Foundation

/// Parses ISO-8601 timestamps from agent transcripts, tolerating both
/// fractional-second (`2026-04-02T04:03:44.500Z`) and whole-second
/// (`2026-04-02T04:03:44Z`) forms.
///
/// Claude transcript timestamps carry fractional seconds; a plain
/// `ISO8601DateFormatter()` (without `.withFractionalSeconds`) fails to parse
/// them and callers silently fall back to file mtime. Some lines may omit the
/// fraction, so both formatters are tried.
///
/// The formatters are `static let` — `ISO8601DateFormatter` is expensive to
/// allocate and this runs on the per-line hot path of large transcripts.
enum TranscriptTimestamp {
    // ISO8601DateFormatter is expensive to allocate, so these are hoisted to
    // static lets on the per-line hot path. `nonisolated(unsafe)` is safe here:
    // once `formatOptions` is set at init we only ever call `date(from:)`, which
    // Foundation documents as thread-safe for a configured formatter (it does not
    // mutate observable state). We never mutate these after construction.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let wholeSecond: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return fractional.date(from: string) ?? wholeSecond.date(from: string)
    }
}
