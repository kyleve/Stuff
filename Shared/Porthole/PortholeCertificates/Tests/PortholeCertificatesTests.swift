import Foundation
import PortholeCertificates
import Testing

struct PortholeCertificatesTests {
    @Test func generatesUniqueCertificatesWithBoundedValidityAndRedactedDescriptions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try PortholeCertificates.generate(name: "Porthole", at: now)
        let second = try PortholeCertificates.generate(name: "Porthole", at: now)
        #expect(first.certificateDER != second.certificateDER)
        #expect(first.privateKeyX963.count == 97)
        #expect(try PortholeCertificates.isValid(certificateDER: first.certificateDER, at: now))
        #expect(try !PortholeCertificates.isValid(
            certificateDER: first.certificateDER,
            at: now.addingTimeInterval(-120),
        ))
        #expect(try !PortholeCertificates.isValid(
            certificateDER: first.certificateDER,
            at: now.addingTimeInterval(366 * 24 * 60 * 60),
        ))
        #expect(!first.description.contains(first.privateKeyX963.base64EncodedString()))
    }

    @Test func malformedCertificateIsAnObservableFailure() {
        #expect(throws: (any Error).self) {
            try PortholeCertificates.isValid(certificateDER: Data([1, 2, 3]), at: Date())
        }
    }
}
