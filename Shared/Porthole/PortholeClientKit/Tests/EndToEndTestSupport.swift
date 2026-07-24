import CryptoKit
import Foundation
@_spi(Testing) import PortholeCore
@testable import PortholeKit

/// A fixture connector on the device side for end-to-end tests: an `echo` action
/// and a subscribable `ticks` source.
final class E2EConnector: PortholeConnector {
    let descriptor = PortholeConnectorDescriptor(
        id: "e2e",
        title: "E2E",
        summary: "Fixture.",
        version: 1,
    )

    func actions() -> [PortholeAction] {
        [
            PortholeAction(
                descriptor: PortholeActionDescriptor(
                    id: "echo",
                    title: "Echo",
                    summary: "Echoes a value.",
                    parameters: .object(["value": .integer()], required: ["value"]),
                    isDestructive: false,
                ),
                handler: { .object(["echoed": $0["value"] ?? .null]) },
            ),
        ]
    }

    func dataSources() -> [PortholeDataSource] {
        [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "ticks",
                    title: "Ticks",
                    summary: "Counter.",
                    rowSchema: .object(["tick": .integer()]),
                    filters: .object([:]),
                    supportsSubscription: true,
                ),
                fetch: { _ in PortholePage(rows: []) },
                subscribe: {
                    AsyncStream { continuation in
                        let task = Task {
                            var tick = 0
                            while !Task.isCancelled {
                                continuation.yield(.object(["tick": .int(Int64(tick))]))
                                tick += 1
                                try? await Task.sleep(for: .milliseconds(2))
                            }
                            continuation.finish()
                        }
                        continuation.onTermination = { _ in task.cancel() }
                    }
                },
            ),
        ]
    }
}

/// Collects the device's pending pairing code so the client can read it.
actor CodeCollector {
    private var code: String?
    private var waiters: [CheckedContinuation<String, Never>] = []

    func set(_ newCode: String?) {
        guard let newCode else { return }
        code = newCode
        for waiter in waiters {
            waiter.resume(returning: newCode)
        }
        waiters.removeAll()
    }

    func waitForCode() async -> String {
        if let code { return code }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

/// Drives the device side of a full session (handshake → secure channel →
/// router) over a transport, using the real PortholeKit types. The mirror of
/// `PortholeServer.accept` minus `NWConnection`.
@MainActor
final class DeviceHarness {
    let porthole: Porthole
    let manager: DevicePairingManager
    let store = InMemoryCredentialStore()
    let codeCollector = CodeCollector()

    init() {
        // The porthole here is only a source of resolved connectors + hello;
        // its own (unused) credential store never opens because start() isn't called.
        porthole = Porthole(configuration: PortholeConfiguration(
            appName: "E2E",
            bundleID: "com.stuff.e2e",
        ))
        porthole.register(E2EConnector())
        let collector = codeCollector
        manager = DevicePairingManager(
            credentials: store,
            onCodeChange: { await collector.set($0) },
        )
    }

    /// Revokes a pairing on the device side.
    func revoke(_ pairingID: UUID) async throws {
        try await manager.revoke(pairingID)
    }

    /// Serves one connection to completion: runs the handshake and, on a session,
    /// the router over a device-role secure channel.
    func serve(transport: some PortholeTransport) -> Task<Void, Never> {
        let connectors = porthole.resolvedConnectors()
        let hello = porthole.helloReply
        let manager = manager
        return Task {
            let reader = TransportFrameReader(transport)
            let sender: @Sendable (Data) async throws -> Void = { try await transport.send($0) }
            let result = await manager.handshake(reader: reader, send: sender)
            guard case let .session(key, _) = result else { return }
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
        }
    }
}

struct E2ETimeout: Error {}

func withE2ETimeout<T: Sendable>(
    _ duration: Duration = .seconds(3),
    _ operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw E2ETimeout()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
