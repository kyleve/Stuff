import Foundation
import Network
import PortholeCore

/// Owns the Bonjour `NWListener`, accepts connections, and for each one runs the
/// handshake and (on session success) a `PortholeSessionRouter` over a
/// `PortholeSecureChannel`. A thin coordinator: the handshake, crypto, and
/// dispatch it wires together are all tested independently over loopback.
final class PortholeServer: @unchecked Sendable {
    private let configuration: PortholeConfiguration
    private let pairingManager: DevicePairingManager
    private let connectors: ResolvedConnectors
    private let hello: HelloReply
    private let onSessionCountChange: @Sendable (Int) async -> Void

    private let queue = DispatchQueue(label: "com.stuff.porthole.server")
    private let sessionLock = NSLock()
    private var sessionCount = 0
    private var listener: NWListener?

    init(
        configuration: PortholeConfiguration,
        pairingManager: DevicePairingManager,
        connectors: ResolvedConnectors,
        hello: HelloReply,
        onSessionCountChange: @escaping @Sendable (Int) async -> Void,
    ) {
        self.configuration = configuration
        self.pairingManager = pairingManager
        self.connectors = connectors
        self.hello = hello
        self.onSessionCountChange = onSessionCountChange
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let listener: NWListener = if let port = configuration.port,
                                      let nwPort = NWEndpoint.Port(rawValue: port)
        {
            try NWListener(using: parameters, on: nwPort)
        } else {
            try NWListener(using: parameters)
        }

        let txt = NWTXTRecord([
            "name": configuration.appName,
            "bundle": configuration.bundleID,
            "device": DeviceInfo.deviceName,
            "ver": String(portholeProtocolVersion),
        ])
        listener.service = NWListener.Service(
            name: configuration.appName,
            type: configuration.serviceType,
            txtRecord: txt,
        )
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                PortholeLog.network
                    .error("Listener failed: \(String(describing: error), privacy: .public)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        let transport = NWConnectionTransport(connection: connection, queue: queue)
        let pairingManager = pairingManager
        let connectors = connectors
        let hello = hello
        Task {
            let reader = TransportFrameReader(transport)
            let sender: @Sendable (Data) async throws -> Void = { try await transport.send($0) }
            let result = await pairingManager.handshake(reader: reader, send: sender)
            switch result {
                case let .session(key, _):
                    await self.changeSessionCount(by: 1)
                    let channel = PortholeSecureChannel(
                        reader: reader,
                        send: sender,
                        close: { await transport.close() },
                        key: key,
                        role: .device,
                    )
                    let router = PortholeSessionRouter(
                        transport: channel,
                        connectors: connectors,
                        hello: hello,
                    )
                    await router.run()
                    await transport.close()
                    await self.changeSessionCount(by: -1)
                case .paired, .rejected:
                    await transport.close()
            }
        }
    }

    private func changeSessionCount(by delta: Int) async {
        let newCount = sessionLock.withLock { () -> Int in
            sessionCount += delta
            return sessionCount
        }
        await onSessionCountChange(newCount)
    }
}
