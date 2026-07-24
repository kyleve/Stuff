import Foundation
import PortholeCore

/// The device-side composition root of Porthole. An app creates exactly one,
/// registers its connectors, and calls ``start()`` to advertise and accept
/// connections. Everything a client can reach flows through the connectors
/// registered here.
///
/// `@MainActor` + `@Observable` so SwiftUI (the pairing UI) can bind to
/// ``state`` directly. The built-in `app` connector is registered automatically;
/// other built-ins (`ui`, `files`, `notifications`, `permissions`) register
/// themselves as they are added to the suite.
@MainActor
@Observable
public final class Porthole {
    public let configuration: PortholeConfiguration
    public let state = PortholeState()

    private let registry = ConnectorRegistry()
    private let credentials: PortholeCredentialStore
    private var sessionTasks: [Task<Void, Never>] = []
    private var server: PortholeServer?
    private var pairingManager: DevicePairingManager?

    public convenience init(configuration: PortholeConfiguration) {
        self.init(
            configuration: configuration,
            credentials: KeychainCredentialStore(service: "com.stuff.porthole.device"),
        )
    }

    /// Testing/advanced seam: inject a credential store (e.g. in-memory) instead
    /// of the login Keychain.
    @_spi(Testing)
    public init(configuration: PortholeConfiguration, credentials: PortholeCredentialStore) {
        self.configuration = configuration
        self.credentials = credentials
        register(AppInfoConnector(appName: configuration.appName, bundleID: configuration.bundleID))
        register(FileBrowserConnector(appGroupIdentifiers: configuration.appGroupIdentifiers))
        #if canImport(UIKit)
            register(ViewTreeConnector())
        #endif
    }

    /// Registers a connector. A duplicate id is a programmer error (asserts in
    /// debug, ignored in release).
    public func register(_ connector: some PortholeConnector) {
        registry.register(connector)
    }

    /// Starts advertising over Bonjour and accepting connections.
    public func start() throws {
        guard server == nil else { return }
        let manager = DevicePairingManager(
            credentials: credentials,
            onCodeChange: { [weak self] code in await self?.setPendingCode(code) },
            onPairedHostsChange: { [weak self] in await self?.refreshPairedHosts() },
        )
        let server = PortholeServer(
            configuration: configuration,
            pairingManager: manager,
            connectors: registry.resolve(),
            hello: helloReply,
            onSessionCountChange: { [weak self] count in await self?.setSessionCount(count) },
        )
        try server.start()
        pairingManager = manager
        self.server = server
        state.isAdvertising = true
        Task { await refreshPairedHosts() }
    }

    /// Stops advertising and closes active sessions.
    public func stop() {
        server?.stop()
        server = nil
        pairingManager = nil
        for task in sessionTasks {
            task.cancel()
        }
        sessionTasks.removeAll()
        state.activeSessionCount = 0
        state.pendingPairingCode = nil
        state.isAdvertising = false
    }

    /// Revokes a pairing so the host can no longer connect.
    public func revoke(_ pairingID: UUID) async throws {
        try credentials.delete(pairingID: pairingID)
        await refreshPairedHosts()
    }

    private func setPendingCode(_ code: String?) {
        state.pendingPairingCode = code
    }

    private func setSessionCount(_ count: Int) {
        state.activeSessionCount = count
    }

    private func refreshPairedHosts() async {
        if let pairingManager {
            state.pairedHosts = await pairingManager.pairedHosts()
        } else {
            state.pairedHosts = loadPairedHosts()
        }
    }

    private func loadPairedHosts() -> [PairedHost] {
        (try? credentials.all())?.compactMap { record in
            guard let metadata = try? JSONDecoder().decode(
                PairedHostMetadata.self,
                from: record.metadata,
            ) else {
                return PairedHost(
                    pairingID: record.pairingID,
                    name: "Unknown",
                    createdAt: .distantPast,
                )
            }
            return PairedHost(
                pairingID: record.pairingID,
                name: metadata.name,
                createdAt: metadata.createdAt,
            )
        } ?? []
    }

    var helloReply: HelloReply {
        HelloReply(
            appName: configuration.appName,
            bundleID: configuration.bundleID,
            deviceName: DeviceInfo.deviceName,
        )
    }

    func resolvedConnectors() -> ResolvedConnectors {
        registry.resolve()
    }

    /// Serves a session over an already-authenticated transport, bypassing the
    /// network/handshake layer. The seam that lets tests drive the full request
    /// router in-process over a `LoopbackTransport`.
    @_spi(Testing)
    public func attach(transport: some PortholeTransport, authenticated _: Bool = true) {
        let router = PortholeSessionRouter(
            transport: transport,
            connectors: registry.resolve(),
            hello: helloReply,
        )
        state.activeSessionCount += 1
        let task = Task { @MainActor [weak self] in
            await router.run()
            self?.state.activeSessionCount -= 1
        }
        sessionTasks.append(task)
    }
}
