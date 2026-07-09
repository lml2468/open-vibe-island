import Foundation
import Testing
@testable import OpenIslandCore

/// Shared pretty-printed, key-sorted JSON config serialization for the hook
/// installers (slice `dedup-installer-serialize`, discovery finding #9 cluster B).
struct JSONConfigSerializationTests {
    private func string(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONConfigSerialization.serialize(object), as: UTF8.self)
    }

    @Test
    func sortsKeysAndPrettyPrints() throws {
        let output = try string(["b": 1, "a": 2])
        // Sorted keys: "a" appears before "b".
        guard let aIndex = output.range(of: "\"a\""),
              let bIndex = output.range(of: "\"b\"") else {
            #expect(Bool(false), "both keys should be present; got: \(output)")
            return
        }
        #expect(aIndex.lowerBound < bIndex.lowerBound)
        // Pretty-printed: contains a newline.
        #expect(output.contains("\n"))
    }

    @Test
    func roundTripsToSameDictionary() throws {
        let original: [String: Any] = ["hooks": ["a", "b"], "version": 1]
        let data = try JSONConfigSerialization.serialize(original)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["version"] as? Int == 1)
        #expect(decoded?["hooks"] as? [String] == ["a", "b"])
    }

    @Test
    func emptyDictionarySerializesToPrettyPrintedEmptyObject() throws {
        #expect(try string([:]) == "{\n\n}")
    }
}
