import CryptoKit
import Foundation
@_spi(Testing) import PortholeCore
@testable import PortholeKit
import Testing

struct DevicePairingManagerTests {
    private func runHandshake(
        _ manager: DevicePairingManager,
        device: some PortholeTransport,
    ) -> Task<HandshakeResult, Never> {
        let reader = TransportFrameReader(device)
        return Task { await manager.handshake(reader: reader, send: { try await device.send($0) }) }
    }

    @Test func pairingSucceedsAndStoresCredential() async throws {
        let store = InMemoryCredentialStore()
        let codeBox = CodeBox()
        let manager = DevicePairingManager(
            credentials: store,
            onCodeChange: { await codeBox.set($0) },
        )
        let (device, client) = LoopbackTransport.makePair()

        let deviceResult = runHandshake(manager, device: device)
        let outcome = try await TestPairingClient.pair(
            transport: client,
            clientName: "MacBook",
            code: { await codeBox.waitForCode() },
        )

        let result = await deviceResult.value
        guard case let .paired(pairingID) = result else {
            Issue.record("Expected .paired, got \(result)")
            return
        }
        #expect(pairingID == outcome.pairingID)
        #expect(try store.key(for: pairingID) == outcome.psk)

        let hosts = await manager.pairedHosts()
        #expect(hosts.contains { $0.pairingID == pairingID && $0.name == "MacBook" })
    }

    @Test func wrongCodeIsRejected() async throws {
        let store = InMemoryCredentialStore()
        let codeBox = CodeBox()
        let manager = DevicePairingManager(
            credentials: store,
            onCodeChange: { await codeBox.set($0) },
        )
        let (device, client) = LoopbackTransport.makePair()

        let deviceResult = runHandshake(manager, device: device)
        await #expect(throws: PortholeError.self) {
            _ = try await TestPairingClient.pair(
                transport: client,
                clientName: "cli",
                code: { await codeBox.waitForCode() },
                overrideCode: { TestPairingClient.differentCode(from: $0) },
            )
        }

        let result = await deviceResult.value
        guard case .rejected(.pairingFailed(.wrongCode)) = result else {
            Issue.record("Expected wrongCode, got \(result)")
            return
        }
        #expect(try store.all().isEmpty)
    }

    @Test func threeWrongAttemptsBurnTheCode() async {
        let store = InMemoryCredentialStore()
        let codeBox = CodeBox()
        let manager = DevicePairingManager(
            credentials: store,
            onCodeChange: { await codeBox.set($0) },
        )

        var lastResult: HandshakeResult?
        for _ in 0 ..< 3 {
            let (device, client) = LoopbackTransport.makePair()
            let deviceResult = runHandshake(manager, device: device)
            _ = try? await TestPairingClient.pair(
                transport: client,
                clientName: "cli",
                code: { await codeBox.waitForCode() },
                overrideCode: { TestPairingClient.differentCode(from: $0) },
            )
            lastResult = await deviceResult.value
        }
        guard case .rejected(.pairingFailed(.tooManyAttempts)) = lastResult else {
            Issue
                .record(
                    "Expected tooManyAttempts on the third attempt, got \(String(describing: lastResult))",
                )
            return
        }
    }

    @Test func expiredCodeIsRejected() async throws {
        let store = InMemoryCredentialStore()
        let clock = MutableClock(Date())
        let codeBox = CodeBox()
        let manager = DevicePairingManager(
            credentials: store,
            codeLifetime: 120,
            now: clock.nowClosure(),
            onCodeChange: { await codeBox.set($0) },
        )
        let (device, client) = LoopbackTransport.makePair()

        let deviceResult = runHandshake(manager, device: device)
        await #expect(throws: PortholeError.self) {
            _ = try await TestPairingClient.pair(
                transport: client,
                clientName: "cli",
                code: { await codeBox.waitForCode() },
                beforeConfirm: { clock.advance(200) },
            )
        }
        let result = await deviceResult.value
        guard case .rejected(.pairingFailed(.expired)) = result else {
            Issue.record("Expected expired, got \(result)")
            return
        }
    }

    @Test func sessionRederivesMatchingKey() async throws {
        // First pair.
        let store = InMemoryCredentialStore()
        let codeBox = CodeBox()
        let manager = DevicePairingManager(
            credentials: store,
            onCodeChange: { await codeBox.set($0) },
        )
        let (pairDevice, pairClient) = LoopbackTransport.makePair()
        let pairDeviceResult = runHandshake(manager, device: pairDevice)
        let outcome = try await TestPairingClient.pair(
            transport: pairClient,
            clientName: "cli",
            code: { await codeBox.waitForCode() },
        )
        _ = await pairDeviceResult.value

        // Then open a session and confirm both sides derive the same key.
        let (device, client) = LoopbackTransport.makePair()
        let deviceResult = runHandshake(manager, device: device)
        let clientKey = try await TestPairingClient.session(
            transport: client,
            pairingID: outcome.pairingID,
            psk: outcome.psk,
        )

        let result = await deviceResult.value
        guard case let .session(deviceKey, pairingID) = result else {
            Issue.record("Expected .session, got \(result)")
            return
        }
        #expect(pairingID == outcome.pairingID)
        #expect(deviceKey == clientKey)
    }

    @Test func sessionForUnknownPairingIsRejected() async throws {
        let store = InMemoryCredentialStore()
        let manager = DevicePairingManager(credentials: store)
        let (device, client) = LoopbackTransport.makePair()

        let deviceResult = runHandshake(manager, device: device)
        await #expect(throws: PortholeError.self) {
            _ = try await TestPairingClient.session(
                transport: client,
                pairingID: UUID(),
                psk: SymmetricKey(size: .bits256),
            )
        }
        let result = await deviceResult.value
        guard case .rejected(.notPaired) = result else {
            Issue.record("Expected notPaired, got \(result)")
            return
        }
    }

    @Test func revokeRemovesPairing() async throws {
        let store = InMemoryCredentialStore()
        let codeBox = CodeBox()
        let manager = DevicePairingManager(
            credentials: store,
            onCodeChange: { await codeBox.set($0) },
        )
        let (device, client) = LoopbackTransport.makePair()
        let deviceResult = runHandshake(manager, device: device)
        let outcome = try await TestPairingClient.pair(
            transport: client,
            clientName: "cli",
            code: { await codeBox.waitForCode() },
        )
        _ = await deviceResult.value

        try await manager.revoke(outcome.pairingID)
        #expect(await manager.pairedHosts().isEmpty)
        #expect(try store.key(for: outcome.pairingID) == nil)
    }
}
