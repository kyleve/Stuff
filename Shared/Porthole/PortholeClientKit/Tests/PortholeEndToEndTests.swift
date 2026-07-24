import CryptoKit
import Foundation
@_spi(Testing) import PortholeClientKit
@_spi(Testing) import PortholeCore
import Testing

/// End-to-end tests running the *real* device (PortholeKit) and client
/// (PortholeClientKit) stacks in one process over a `LoopbackTransport`: pairing,
/// the encrypted session handshake, and request/response/streaming through the
/// secure channel.
@MainActor
struct PortholeEndToEndTests {
    private nonisolated func discoveredApp() -> DiscoveredApp {
        DiscoveredApp(
            endpointName: "E2E",
            appName: "E2E",
            bundleID: "com.stuff.e2e",
            deviceName: "TestDevice",
            protocolVersion: portholeProtocolVersion,
        )
    }

    /// Pairs over one loopback pair; returns the harness, client store, and the
    /// resulting PairedApp so a session test can follow.
    private func pair(
        harness: DeviceHarness,
        clientStore: InMemoryCredentialStore,
    ) async throws -> PairedApp {
        let (device, client) = LoopbackTransport.makePair()
        let deviceTask = harness.serve(transport: device)
        let pairingClient = PortholePairingClient(credentials: clientStore, clientName: "TestMac")
        let collector = harness.codeCollector
        let paired = try await withE2ETimeout {
            try await pairingClient.pair(
                over: client,
                app: discoveredApp(),
                codeProvider: { await collector.waitForCode() },
            )
        }
        _ = await deviceTask.value
        return paired
    }

    @Test func pairsAndOpensAnAuthenticatedSession() async throws {
        let harness = DeviceHarness()
        let clientStore = InMemoryCredentialStore()
        let paired = try await pair(harness: harness, clientStore: clientStore)

        // The client persisted the pairing.
        #expect(paired.bundleID == "com.stuff.e2e")
        #expect(try clientStore.key(for: paired.pairingID) != nil)

        // Open a session over a fresh connection.
        let (device, client) = LoopbackTransport.makePair()
        let deviceTask = harness.serve(transport: device)
        let session = try await withE2ETimeout {
            let psk = try clientStore.key(for: paired.pairingID)!
            return try await PortholeClient(credentials: clientStore, clientName: "TestMac")
                .connect(over: client, pairingID: paired.pairingID, psk: psk)
        }

        let deviceInfo = await session.deviceInfo
        #expect(deviceInfo?.appName == "E2E")

        let manifests = try await withE2ETimeout { try await session.manifest() }
        let ids = Set(manifests.map(\.connector.id))
        #expect(ids.contains("app"))
        #expect(ids.contains("e2e"))

        await session.close()
        deviceTask.cancel()
    }

    @Test func invokeAndQueryAcrossTheSecureChannel() async throws {
        let harness = DeviceHarness()
        let clientStore = InMemoryCredentialStore()
        let paired = try await pair(harness: harness, clientStore: clientStore)

        let (device, client) = LoopbackTransport.makePair()
        let deviceTask = harness.serve(transport: device)
        let storedKey = try clientStore.key(for: paired.pairingID)
        let psk = try #require(storedKey)
        let session = try await withE2ETimeout {
            try await PortholeClient(credentials: clientStore).connect(
                over: client,
                pairingID: paired.pairingID,
                psk: psk,
            )
        }

        let echoed = try await withE2ETimeout {
            try await session.invoke(
                .init(connector: "e2e", action: "echo"),
                parameters: ["value": 21],
            )
        }
        #expect(echoed["echoed"]?.intValue == 21)

        let page = try await withE2ETimeout {
            try await session.query(.init(connector: "app", source: "app-info"), PortholeQuery())
        }
        #expect(page.rows.first?["bundleID"]?.stringValue == "com.stuff.e2e")

        await session.close()
        deviceTask.cancel()
    }

    @Test func subscribeStreamsEventsAcrossTheSecureChannel() async throws {
        let harness = DeviceHarness()
        let clientStore = InMemoryCredentialStore()
        let paired = try await pair(harness: harness, clientStore: clientStore)

        let (device, client) = LoopbackTransport.makePair()
        let deviceTask = harness.serve(transport: device)
        let storedKey = try clientStore.key(for: paired.pairingID)
        let psk = try #require(storedKey)
        let session = try await withE2ETimeout {
            try await PortholeClient(credentials: clientStore).connect(
                over: client,
                pairingID: paired.pairingID,
                psk: psk,
            )
        }

        let ticks = try await withE2ETimeout {
            try await session.subscribe(.init(connector: "e2e", source: "ticks"))
        }
        let firstThree = try await withE2ETimeout { () -> [Int64] in
            var collected: [Int64] = []
            for try await value in ticks {
                if let tick = value["tick"]?.intValue { collected.append(tick) }
                if collected.count == 3 { break }
            }
            return collected
        }
        #expect(firstThree == [0, 1, 2])

        await session.close()
        deviceTask.cancel()
    }

    @Test func wrongCodeFailsPairing() async throws {
        let harness = DeviceHarness()
        let clientStore = InMemoryCredentialStore()
        let (device, client) = LoopbackTransport.makePair()
        let deviceTask = harness.serve(transport: device)
        let pairingClient = PortholePairingClient(credentials: clientStore, clientName: "TestMac")
        let collector = harness.codeCollector

        await #expect(throws: PortholeError.self) {
            try await withE2ETimeout {
                try await pairingClient.pair(
                    over: client,
                    app: self.discoveredApp(),
                    codeProvider: {
                        let real = await collector.waitForCode()
                        return (Int(real) ?? 0) == 0 ? "111111" : "000000"
                    },
                )
            }
        }
        _ = await deviceTask.value
        #expect(try clientStore.all().isEmpty)
    }

    @Test func revokedPairingCannotOpenASession() async throws {
        let harness = DeviceHarness()
        let clientStore = InMemoryCredentialStore()
        let paired = try await pair(harness: harness, clientStore: clientStore)

        // Revoke on the device side.
        try await harness.revoke(paired.pairingID)

        let (device, client) = LoopbackTransport.makePair()
        let deviceTask = harness.serve(transport: device)
        let storedKey = try clientStore.key(for: paired.pairingID)
        let psk = try #require(storedKey)
        await #expect(throws: PortholeError.self) {
            try await withE2ETimeout {
                _ = try await PortholeClient(credentials: clientStore).connect(
                    over: client,
                    pairingID: paired.pairingID,
                    psk: psk,
                )
            }
        }
        deviceTask.cancel()
    }
}
