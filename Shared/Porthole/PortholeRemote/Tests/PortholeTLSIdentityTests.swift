import Foundation
@testable import PortholeRemote
import Testing

struct PortholeTLSIdentityTests {
    @Test func selfSignedIdentityRoundTripsWithoutChangingItsPin() throws {
        let now = Date()
        let identity = try PortholeTLSIdentity.generate(name: "Porthole test", at: now)
        try identity.validate(at: now)
        let decoded = try JSONDecoder().decode(
            PortholeTLSIdentity.self,
            from: JSONEncoder().encode(identity),
        )
        #expect(decoded.fingerprint == identity.fingerprint)
        #expect(decoded.fingerprint.count == 32)
        _ = try decoded.securityIdentity()
        #expect(identity.description.contains("redacted"))
        #expect(throws: PortholeRemoteError.invalidIdentity) {
            try identity.validate(at: now.addingTimeInterval(366 * 24 * 60 * 60))
        }
    }
}
