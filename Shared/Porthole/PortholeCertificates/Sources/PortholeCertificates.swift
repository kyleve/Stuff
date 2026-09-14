import Crypto
import Foundation
import SwiftASN1
import X509

/// Native certificate construction returns opaque bytes. No X509 type crosses this module boundary.
public enum PortholeCertificates {
    public struct Material: Sendable, CustomStringConvertible {
        public let certificateDER: Data
        public let privateKeyX963: Data

        public var description: String {
            "PortholeCertificates.Material(<private key redacted>)"
        }
    }

    public static func generate(name: String, at now: Date) throws -> Material {
        let key = P256.Signing.PrivateKey()
        let distinguishedName = try DistinguishedName { CommonName(name) }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(key.publicKey),
            notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(365 * 24 * 60 * 60),
            issuer: distinguishedName,
            subject: distinguishedName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate
                .Extensions { Critical(BasicConstraints.notCertificateAuthority) },
            issuerPrivateKey: .init(key),
        )
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        return Material(
            certificateDER: Data(serializer.serializedBytes),
            privateKeyX963: key.x963Representation,
        )
    }

    /// This checks the certificate encoding and validity interval. The caller must authenticate its
    /// pin.
    public static func isValid(certificateDER: Data, at now: Date) throws -> Bool {
        let certificate = try Certificate(derEncoded: Array(certificateDER))
        return certificate.notValidBefore <= now && certificate.notValidAfter > now
    }
}
