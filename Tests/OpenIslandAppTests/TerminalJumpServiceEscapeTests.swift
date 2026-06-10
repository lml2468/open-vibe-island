import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct TerminalJumpServiceEscapeTests {
    /// Helper: wrap the escaped value in a JSON string and confirm it decodes
    /// back to exactly the original — i.e. no breakout / field injection.
    private func roundTrips(_ original: String) -> Bool {
        let escaped = TerminalJumpService.escapeJSONStringContents(original)
        let json = "{\"v\":\"\(escaped)\"}".data(using: .utf8)!
        struct Box: Decodable { let v: String }
        guard let decoded = try? JSONDecoder().decode(Box.self, from: json) else {
            return false
        }
        return decoded.v == original
    }

    @Test
    func escapesDoubleQuoteWithoutBreakout() {
        #expect(roundTrips("abc\"}"))
        #expect(roundTrips("\"injected\":\"x"))
    }

    @Test
    func escapesBackslash() {
        #expect(roundTrips("a\\b"))
        #expect(roundTrips("\\"))
    }

    @Test
    func escapesControlCharacters() {
        #expect(roundTrips("line1\nline2"))
        #expect(roundTrips("tab\tend"))
        #expect(roundTrips("carriage\rreturn"))
        #expect(roundTrips("null\u{0000}byte"))
        #expect(roundTrips("bell\u{0007}"))
    }

    @Test
    func preservesNormalUnicode() {
        #expect(roundTrips("open-island"))
        #expect(roundTrips("会话 1 · café 🎯"))
    }

    @Test
    func escapedQuoteCannotInjectAdditionalJSONField() {
        // A classic injection attempt: close the string and add a field.
        let malicious = "x\",\"admin\":true"
        let escaped = TerminalJumpService.escapeJSONStringContents(malicious)
        let json = "{\"surface_id\":\"\(escaped)\"}".data(using: .utf8)!
        let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        // Only the single intended key survives; no injected "admin" field.
        #expect(object?.keys.count == 1)
        #expect(object?["admin"] == nil)
        #expect(object?["surface_id"] as? String == malicious)
    }
}

struct AppModelBridgeBackoffTests {
    @Test
    func backoffDoublesUntilCapped() {
        let max: Duration = .seconds(30)
        var delay: Duration = .seconds(2)

        delay = AppModel.nextBridgeReconnectDelay(after: delay, max: max)
        #expect(delay == .seconds(4))
        delay = AppModel.nextBridgeReconnectDelay(after: delay, max: max)
        #expect(delay == .seconds(8))
        delay = AppModel.nextBridgeReconnectDelay(after: delay, max: max)
        #expect(delay == .seconds(16))
        // 16 * 2 = 32 → capped at 30
        delay = AppModel.nextBridgeReconnectDelay(after: delay, max: max)
        #expect(delay == .seconds(30))
        // Stays at the cap.
        delay = AppModel.nextBridgeReconnectDelay(after: delay, max: max)
        #expect(delay == .seconds(30))
    }
}
