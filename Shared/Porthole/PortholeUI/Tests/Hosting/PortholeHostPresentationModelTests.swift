import Foundation
import PortholeRemote
@testable import PortholeUI
import Testing

@MainActor
struct PortholeHostPresentationModelTests {
    @Test func createsCredentialsAndListenerOnlyAfterExplicitEnable() async {
        let host = FakeHost()
        let factory = FakeFactory(host: host, pausesCreation: false)
        let model = PortholeHostPresentationModel(factory: factory)
        #expect(await factory.creations == 0)
        #expect(await host.starts == 0)
        await model.enable()
        #expect(await factory.creations == 1)
        #expect(await host.starts == 1)
        #expect(model.activeSession != nil)
        await model.disable()
        #expect(await host.stops == 1)
        #expect(model.activeSession == nil)
    }

    @Test func disableDuringCredentialCreationPreventsListening() async {
        let host = FakeHost()
        let factory = FakeFactory(host: host, pausesCreation: true)
        let model = PortholeHostPresentationModel(factory: factory)
        let activation = Task { await model.enable() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await factory.creations == 0, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(await factory.creations == 1)
        await model.disable()
        await factory.resume()
        await activation.value
        #expect(await host.starts == 0)
        #expect(await host.stops == 1)
        #expect(model.activeSession == nil)
    }

    private actor FakeFactory: PortholeHostCreating {
        let host: FakeHost
        let pausesCreation: Bool
        private(set) var creations = 0
        private var continuation: CheckedContinuation<Void, Never>?

        init(host: FakeHost, pausesCreation: Bool) {
            self.host = host; self.pausesCreation = pausesCreation
        }

        func create() async throws -> any PortholeHosting {
            creations += 1
            if pausesCreation { await withCheckedContinuation { continuation = $0 } }
            return host
        }

        func resume() {
            continuation?.resume(); continuation = nil
        }
    }

    private actor FakeHost: PortholeHosting {
        private(set) var starts = 0
        private(set) var stops = 0
        func start() {
            starts += 1
        }

        func stop() {
            stops += 1
        }

        func beginEnrollment() throws -> PortholeEnrollmentInvitation {
            throw PortholeRemoteError
                .invalidEnrollment
        }

        func cancelEnrollment() {}
        func peers() -> [PortholeTrustedPeer] {
            []
        }

        func revoke(peerID _: UUID) {}
    }
}
