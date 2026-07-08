import Foundation
import Testing
@testable import OpenIslandCore

/// Auth-hardening contract for `WatchHTTPEndpoint` (slice `watch-auth-hardening`).
///
/// Two defense-in-depth fixes on the Watch/iPhone bridge auth path:
///  - bearer-token verification must be constant-time and must not early-return
///    across the token set (timing side-channel);
///  - the pairing code must have a larger keyspace than the original 4 digits.
///
/// The transport-level exposure (plain HTTP / no TLS, discovery finding #1) is
/// intentionally NOT addressed here — that needs a separate threat-model call.
struct WatchAuthHardeningTests {

    // MARK: - A1: constant-time equality helper

    @Test
    func constantTimeEqualsMatchesIdenticalStrings() {
        #expect(WatchHTTPEndpoint.constantTimeEquals("a-token-value", "a-token-value"))
    }

    @Test
    func constantTimeEqualsRejectsFirstByteDifference() {
        #expect(WatchHTTPEndpoint.constantTimeEquals("Xoken", "token") == false)
    }

    @Test
    func constantTimeEqualsRejectsLastByteDifference() {
        #expect(WatchHTTPEndpoint.constantTimeEquals("tokenX", "tokenY") == false)
    }

    @Test
    func constantTimeEqualsRejectsUnequalLengths() {
        #expect(WatchHTTPEndpoint.constantTimeEquals("token", "token-longer") == false)
    }

    @Test
    func constantTimeEqualsTreatsEmptyStringsAsEqual() {
        #expect(WatchHTTPEndpoint.constantTimeEquals("", ""))
    }

    // MARK: - A2: token verification seam (uses the constant-time helper,
    //             no early-out across the set, behavior preserved)

    @Test
    func authorizesTokenPresentInSet() {
        let tokens: Set<String> = ["alpha", "beta", "gamma"]
        #expect(WatchHTTPEndpoint.isAuthorizedToken("beta", among: tokens))
    }

    @Test
    func rejectsTokenAbsentFromSet() {
        let tokens: Set<String> = ["alpha", "beta", "gamma"]
        #expect(WatchHTTPEndpoint.isAuthorizedToken("delta", among: tokens) == false)
    }

    @Test
    func rejectsAnyTokenAgainstEmptySet() {
        #expect(WatchHTTPEndpoint.isAuthorizedToken("alpha", among: []) == false)
    }

    @Test
    func extractsBearerTokenFromAuthorizationHeader() {
        #expect(WatchHTTPEndpoint.bearerToken(from: ["Authorization": "Bearer abc123"]) == "abc123")
        // lower-cased header key is also accepted (HTTP headers are case-insensitive)
        #expect(WatchHTTPEndpoint.bearerToken(from: ["authorization": "Bearer xyz"]) == "xyz")
    }

    @Test
    func rejectsMissingAuthorizationHeader() {
        #expect(WatchHTTPEndpoint.bearerToken(from: [:]) == nil)
    }

    @Test
    func rejectsMalformedAuthorizationHeader() {
        // No "Bearer " scheme prefix → not a usable token.
        #expect(WatchHTTPEndpoint.bearerToken(from: ["Authorization": "abc123"]) == nil)
        #expect(WatchHTTPEndpoint.bearerToken(from: ["Authorization": "Basic abc123"]) == nil)
    }

    // MARK: - A3: pairing code generator + larger keyspace

    @Test
    func makePairingCodeHasRequestedLengthAndDigitsOnly() {
        for length in [6, 8, 10] {
            let code = WatchHTTPEndpoint.makePairingCode(length: length)
            #expect(code.count == length)
            #expect(code.allSatisfy { $0.isNumber })
        }
    }

    @Test
    func configuredPairingCodeLengthIsAtLeastSix() {
        // >= 6 digits => >= 1,000,000 combinations (100x the original 4-digit space).
        #expect(WatchHTTPEndpoint.pairingCodeLength >= 6)
    }
}
