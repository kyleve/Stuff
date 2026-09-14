import CryptoKit
import Foundation
import Network
import os
import PortholeCertificates
import Security

enum PortholeTLS {
    static let queue = DispatchQueue(label: "Porthole.Remote.Network")
    private static let log = Logger(subsystem: "com.stuff.porthole", category: "TLS")

    static func server(
        identity: PortholeTLSIdentity,
        trust: PortholePeerTrust,
        enrollment: Bool,
    ) throws -> NWParameters {
        let tls = try options(identity: identity)
        sec_protocol_options_set_peer_authentication_required(
            tls.securityProtocolOptions,
            !enrollment,
        )
        if !enrollment {
            sec_protocol_options_set_verify_block(
                tls.securityProtocolOptions,
                { _, securityTrust, complete in
                    do {
                        let certificate = try leafCertificate(trust: securityTrust)
                        try complete(trust.peer(for: certificate, at: Date()) != nil)
                    } catch {
                        log
                            .error(
                                "Rejected client certificate: \(error.localizedDescription, privacy: .public)",
                            )
                        complete(false)
                    }
                },
                queue,
            )
        }
        return parameters(tls: tls)
    }

    static func client(identity: PortholeTLSIdentity?, serverPin: Data) throws -> NWParameters {
        guard serverPin.count == 32 else { throw PortholeRemoteError.invalidIdentity }
        let tls = try options(identity: identity)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            do {
                let bytes = try leafCertificate(trust: trust)
                let valid = try PortholeCertificates.isValid(certificateDER: bytes, at: Date())
                complete(valid && Data(SHA256.hash(data: bytes)) == serverPin)
            } catch {
                log
                    .error(
                        "Rejected server certificate: \(error.localizedDescription, privacy: .public)",
                    )
                complete(false)
            }
        }, queue)
        return parameters(tls: tls)
    }

    static func peerCertificate(connection: NWConnection) throws -> Data {
        guard let metadata = connection
            .metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
        else {
            throw PortholeRemoteError.untrustedPeer
        }
        let bytes = OSAllocatedUnfairLock<Data?>(initialState: nil)
        let available = sec_protocol_metadata_access_peer_certificate_chain(metadata
            .securityProtocolMetadata)
        { certificate in
            let reference = sec_certificate_copy_ref(certificate).takeRetainedValue()
            bytes.withLock { current in
                if current == nil { current = SecCertificateCopyData(reference) as Data }
            }
        }
        guard available,
              let certificate = bytes.withLock({ $0 })
        else { throw PortholeRemoteError.untrustedPeer }
        return certificate
    }

    private static func options(identity: PortholeTLSIdentity?) throws -> NWProtocolTLS.Options {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        if let identity {
            guard let native = try sec_identity_create(identity.securityIdentity())
            else { throw PortholeRemoteError.invalidIdentity }
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, native)
        }
        return tls
    }

    private static func parameters(tls: NWProtocolTLS.Options) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    private static func leafCertificate(trust: sec_trust_t) throws -> Data {
        let reference = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(reference) as? [SecCertificate],
              let leaf = chain.first
        else {
            throw PortholeRemoteError.untrustedPeer
        }
        return SecCertificateCopyData(leaf) as Data
    }
}
