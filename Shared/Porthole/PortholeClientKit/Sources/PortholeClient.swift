import CryptoKit
import Foundation
import Network
import PortholeCore

/// The entry point for talking to paired device apps from the Mac. Lists stored
/// pairings, and opens an authenticated ``PortholeSession`` to one by
/// re-discovering its endpoint and running the session handshake.
public final class PortholeClient: Sendable {
    private let credentials: PortholeCredentialStore
    private let clientName: String
    private let serviceType: String

    public init(
        credentials: PortholeCredentialStore,
        clientName: String = defaultPortholeClientName(),
        serviceType: String = "_porthole._tcp",
    ) {
        self.credentials = credentials
        self.clientName = clientName
        self.serviceType = serviceType
    }

    /// Convenience: a client backed by the shared login keychain.
    public convenience init(clientName: String = defaultPortholeClientName()) {
        self.init(
            credentials: KeychainCredentialStore(service: PortholeCredentialService.client),
            clientName: clientName,
        )
    }

    /// The apps this Mac has paired with.
    public func pairedApps() throws -> [PairedApp] {
        try credentials.all().compactMap { try? JSONDecoder().decode(
            PairedApp.self,
            from: $0.metadata,
        ) }
    }

    /// Forgets a pairing locally (removes the stored credential).
    public func unpair(_ paired: PairedApp) throws {
        try credentials.delete(pairingID: paired.pairingID)
    }

    /// Re-discovers the paired app on the network and opens a session.
    public func connect(
        to paired: PairedApp,
        discoveryTimeout: Duration = .seconds(5),
    ) async throws -> PortholeSession {
        guard let psk = try credentials.key(for: paired.pairingID)
        else { throw PortholeClientError.notPaired }
        let endpoint = try await findEndpoint(for: paired, timeout: discoveryTimeout)
        let transport = makeConnectionTransport(to: endpoint)
        return try await establishSession(over: transport, pairingID: paired.pairingID, psk: psk)
    }

    /// Testing/advanced seam: open a session over an arbitrary transport with a
    /// known PSK, bypassing discovery.
    @_spi(Testing)
    public func connect(
        over transport: some PortholeTransport,
        pairingID: UUID,
        psk: SymmetricKey,
    ) async throws -> PortholeSession {
        try await establishSession(over: transport, pairingID: pairingID, psk: psk)
    }

    private func establishSession(
        over transport: some PortholeTransport,
        pairingID: UUID,
        psk: SymmetricKey,
    ) async throws -> PortholeSession {
        let reader = TransportFrameReader(transport)
        let sender: @Sendable (Data) async throws -> Void = { try await transport.send($0) }
        let sessionKey = try await ClientHandshake.session(
            reader: reader,
            send: sender,
            pairingID: pairingID,
            psk: psk,
        )
        let channel = PortholeSecureChannel(
            reader: reader,
            send: sender,
            close: { await transport.close() },
            key: sessionKey,
            role: .client,
        )
        let session = PortholeSession(transport: channel)
        try await session.start(clientName: clientName)
        return session
    }

    private func findEndpoint(for paired: PairedApp, timeout: Duration) async throws -> NWEndpoint {
        let browser = PortholeBrowser(serviceType: serviceType)
        return try await withDeadline(timeout) {
            for await apps in browser.discovered() {
                if let match = apps
                    .first(where: {
                        $0.bundleID == paired.bundleID && $0.deviceName == paired.deviceName
                    }),
                    let endpoint = match.endpoint
                {
                    return endpoint
                }
            }
            throw PortholeClientError.deviceNotFound
        }
    }
}
