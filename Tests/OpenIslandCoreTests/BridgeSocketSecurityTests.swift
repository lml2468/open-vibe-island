import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

/// Covers the control-socket hardening (brief `bridge-security`, A2/A3):
/// the bound socket must be owner-only (0600), the same-user peer predicate
/// must accept a same-uid connection, and a real same-user client must still
/// connect end-to-end (no regression from the peer-uid gate).
struct BridgeSocketSecurityTests {
    @Test
    func boundSocketIsOwnerOnly() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let attrs = try FileManager.default.attributesOfItem(atPath: socketURL.path)
        let posix = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0xFFFF
        // No group/other bits — only S_IRUSR | S_IWUSR (0600).
        #expect(posix & UInt16(S_IRWXG | S_IRWXO) == 0)
        #expect(posix & UInt16(S_IRUSR | S_IWUSR) == UInt16(S_IRUSR | S_IWUSR))
    }

    @Test
    func sameUserPeerIsTrustedAndConnectsEndToEnd() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        // A real client from the same uid must still connect and exchange a
        // command — the peer-uid gate must not lock out our own process. If the
        // gate had dropped the connection, the send would fail once the server
        // closed the fd.
        let client = LocalBridgeClient(socketURL: socketURL)
        // Retain the stream: dropping it triggers onTermination → disconnect,
        // which would close the fd before we can send.
        let stream = try client.connect()
        defer { client.disconnect() }

        try await client.send(.registerClient(role: .observer))
        withExtendedLifetime(stream) {}
    }

    /// The peer-trust predicate accepts a same-uid socket. A connected
    /// socketpair shares this process's uid on both ends, so it must be trusted;
    /// a mismatching expected uid must be rejected (default-deny).
    @Test
    func peerTrustPredicateMatchesUID() {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            Issue.record("socketpair unavailable")
            return
        }
        defer { close(fds[0]); close(fds[1]) }

        #expect(isTrustedLocalPeer(fds[0], expectedUID: getuid()) == true)
        // A uid we are definitely not running as → rejected.
        let impossibleUID = getuid() &+ 999_999
        #expect(isTrustedLocalPeer(fds[0], expectedUID: impossibleUID) == false)
    }
}
