import Foundation
import PortholeCore

/// Pairs the Mac with a discovered device app: runs the pair handshake and
/// persists the resulting credential so every local surface (CLI, MCP, app) can
/// connect afterward.
public final class PortholePairingClient: Sendable {
    private let credentials: PortholeCredentialStore
    private let clientName: String

    public init(
        credentials: PortholeCredentialStore,
        clientName: String = defaultPortholeClientName(),
    ) {
        self.credentials = credentials
        self.clientName = clientName
    }

    /// Convenience: a pairing client backed by the shared login keychain.
    public convenience init(clientName: String = defaultPortholeClientName()) {
        self.init(
            credentials: KeychainCredentialStore(service: PortholeCredentialService.client),
            clientName: clientName,
        )
    }

    /// Connects to `app` and pairs, prompting for the device's code via
    /// `codeProvider`. Persists the credential and returns the stored pairing.
    public func pair(
        with app: DiscoveredApp,
        codeProvider: @escaping @Sendable () async -> String,
    ) async throws -> PairedApp {
        guard let endpoint = app.endpoint else { throw PortholeClientError.deviceNotFound }
        let transport = makeConnectionTransport(to: endpoint)
        return try await pair(over: transport, app: app, codeProvider: codeProvider)
    }

    /// Testing/advanced seam: run pairing over an arbitrary transport.
    @_spi(Testing)
    public func pair(
        over transport: some PortholeTransport,
        app: DiscoveredApp,
        codeProvider: @escaping @Sendable () async -> String,
    ) async throws -> PairedApp {
        let reader = TransportFrameReader(transport)
        let sender: @Sendable (Data) async throws -> Void = { try await transport.send($0) }
        let result = try await ClientHandshake.pair(
            reader: reader,
            send: sender,
            clientName: clientName,
            code: codeProvider,
        )
        let paired = PairedApp(
            pairingID: result.pairingID,
            appName: app.appName,
            bundleID: app.bundleID,
            deviceName: app.deviceName,
            pairedAt: Date(),
        )
        try credentials.save(
            pairingID: result.pairingID,
            key: result.psk,
            metadata: JSONEncoder().encode(paired),
        )
        await transport.close()
        return paired
    }
}
