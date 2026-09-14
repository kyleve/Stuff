import Foundation
import PortholeCore
import PortholeRemote

#if canImport(UIKit)
    /// One fixture model survives measurement and accessibility rehosting without restarting
    /// enrollment.
    @MainActor
    final class PortholeHostingSnapshotFixture {
        let model = PortholeHostPresentationModel(factory: PortholeSnapshotHostFactory())
        private let activate: Bool
        private var preparation: Task<Void, Never>?

        init(activate: Bool) {
            self.activate = activate
        }

        func prepare() async {
            guard activate else { return }
            if let preparation {
                await preparation.value
                return
            }
            // Capture hooks and a reattached view can arrive together. Their cancellation must
            // not restart a completed invitation or leave another capture waiting on view state.
            let preparation = Task { [model] in
                await model.enable()
                guard let session = model.activeSession else {
                    preconditionFailure("The snapshot host did not become active.")
                }
                await session.createInvitation()
                guard case .invitation = session.enrollment else {
                    preconditionFailure("The snapshot host did not create its invitation.")
                }
            }
            self.preparation = preparation
            await preparation.value
        }
    }

    private struct PortholeSnapshotHostFactory: PortholeHostCreating {
        func create() async throws -> any PortholeHosting {
            PortholeSnapshotHost()
        }
    }

    private actor PortholeSnapshotHost: PortholeHosting {
        func start() {}
        func stop() {}
        func cancelEnrollment() {}
        func beginEnrollment() throws -> PortholeEnrollmentInvitation {
            let fixture = PortholeValue.object([
                "serviceName": .string("Where on iPhone"),
                "serverCertificatePin": .string(Data(repeating: 1, count: 32)
                    .base64EncodedString()),
                "token": .string(Data(repeating: 2, count: 32).base64EncodedString()),
                "expiresAt": .number(1_600_000_000),
            ])
            return try fixture.decode(PortholeEnrollmentInvitation.self)
        }

        func peers() -> [PortholeTrustedPeer] {
            [.init(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "Development Mac",
                certificateDER: Data(),
                enrolledAt: Date(timeIntervalSince1970: 1_700_000_000),
            )]
        }

        func revoke(peerID _: UUID) {}
    }
#endif
