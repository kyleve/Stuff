import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Observation
import PortholeRemote

/// Enrollment text exists only in this trusted native presentation state.
@MainActor @Observable
final class PortholeHostedSession {
    struct Invitation {
        let text: String
        let expiresAt: Date
        let image: CGImage?

        init(_ invitation: PortholeEnrollmentInvitation) throws {
            text = try invitation.encodedInvitation()
            expiresAt = invitation.expiresAt
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(text.utf8)
            filter.correctionLevel = "M"
            if let output = filter.outputImage {
                image = CIContext().createCGImage(output, from: output.extent)
            } else { image = nil }
        }
    }

    enum Enrollment {
        case closed, creating(UUID), invitation(Invitation), failed(String)
    }

    let id = UUID()
    let server: any PortholeHosting
    private(set) var peers: [PortholeTrustedPeer] = []
    private(set) var enrollment: Enrollment = .closed
    private(set) var revocationError: String?

    init(server: any PortholeHosting) {
        self.server = server
    }

    func refresh() async {
        let currentPeers = await server.peers()
        let addedPeer = currentPeers.contains { current in !peers.contains { $0.id == current.id } }
        peers = currentPeers
        if addedPeer, case .invitation = enrollment { await cancelInvitation() }
        if case let .invitation(invitation) = enrollment, invitation.expiresAt <= Date() {
            await cancelInvitation()
        }
    }

    func createInvitation() async {
        let operationID = UUID()
        enrollment = .creating(operationID)
        do {
            let invitation = try await server.beginEnrollment()
            try Task.checkCancellation()
            guard case .creating(operationID) = enrollment else { return }
            enrollment = try .invitation(Invitation(invitation))
        } catch is CancellationError {
            await cancelInvitation()
        } catch {
            PortholeUILog.failures
                .error("Remote invitation failed: \(String(describing: error), privacy: .private)")
            if case .creating(operationID) = enrollment {
                enrollment = .failed(error.localizedDescription)
            }
        }
    }

    func cancelInvitation() async {
        enrollment = .closed
        await server.cancelEnrollment()
    }

    func clearInvitation() {
        enrollment = .closed
    }

    func revoke(_ peer: PortholeTrustedPeer) async {
        do {
            try await server.revoke(peerID: peer.id)
            revocationError = nil
            await refresh()
        } catch {
            PortholeUILog.failures
                .error(
                    "Remote peer revocation failed: \(String(describing: error), privacy: .private)",
                )
            revocationError = error.localizedDescription
        }
    }

    func observe() async {
        do {
            while !Task.isCancelled {
                await refresh()
                try await ContinuousClock().sleep(for: .seconds(1))
            }
        } catch is CancellationError {
            return
        } catch {
            PortholeUILog.failures
                .error(
                    "Remote peer observation failed: \(String(describing: error), privacy: .private)",
                )
            revocationError = error.localizedDescription
        }
    }
}
