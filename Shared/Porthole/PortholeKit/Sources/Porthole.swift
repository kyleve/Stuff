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
    private var sessionTasks: [Task<Void, Never>] = []

    public init(configuration: PortholeConfiguration) {
        self.configuration = configuration
        register(AppInfoConnector(appName: configuration.appName, bundleID: configuration.bundleID))
    }

    /// Registers a connector. A duplicate id is a programmer error (asserts in
    /// debug, ignored in release).
    public func register(_ connector: some PortholeConnector) {
        registry.register(connector)
    }

    /// Starts advertising and accepting connections. Wired in the network layer.
    public func start() throws {
        // Implemented in the network layer (PortholeServer).
    }

    /// Stops advertising and closes active sessions.
    public func stop() {
        for task in sessionTasks {
            task.cancel()
        }
        sessionTasks.removeAll()
        state.activeSessionCount = 0
        state.isAdvertising = false
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
