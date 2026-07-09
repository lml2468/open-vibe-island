import Foundation
import Testing
@testable import OpenIslandCore

/// Shared root-object loading for the JSON hook installers (slice
/// `dedup-installer-loadroot`, discovery finding #9 cluster B). Preserves the
/// installer-config-safety behaviors: nil→[:], valid dict→dict, non-dict→throw
/// (never reset-on-parse-failure), carrying each caller's own error.
struct JSONConfigLoadRootTests {
    private struct SentinelError: Error, Equatable {}

    @Test
    func nilDataReturnsEmptyDictionary() throws {
        let root = try JSONConfigSerialization.loadRootObject(from: nil, invalidError: SentinelError())
        #expect(root.isEmpty)
    }

    @Test
    func validObjectIsReturned() throws {
        let data = Data(#"{"a":1,"hooks":["x"]}"#.utf8)
        let root = try JSONConfigSerialization.loadRootObject(from: data, invalidError: SentinelError())
        #expect(root["a"] as? Int == 1)
        #expect(root["hooks"] as? [String] == ["x"])
    }

    @Test
    func nonDictionaryJSONThrowsGivenErrorAndDoesNotReset() {
        // A top-level JSON array is valid JSON but not a dictionary — the loader
        // must THROW (never fall back to [:] and overwrite the user's file).
        let data = Data("[1, 2, 3]".utf8)
        do {
            _ = try JSONConfigSerialization.loadRootObject(from: data, invalidError: SentinelError())
            #expect(Bool(false), "expected a throw for non-dictionary JSON, got a value")
        } catch let error as SentinelError {
            #expect(error == SentinelError())
        } catch {
            #expect(Bool(false), "expected the injected SentinelError, got \(error)")
        }
    }

    @Test
    func malformedJSONThrows() {
        let data = Data("{not valid json".utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONConfigSerialization.loadRootObject(from: data, invalidError: SentinelError())
        }
    }
}
