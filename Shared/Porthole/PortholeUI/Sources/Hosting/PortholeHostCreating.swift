import Foundation
import PortholeCore
import PortholeRemote

/// The native host boundary keeps listener and credential creation behind explicit activation.
public protocol PortholeHosting: Sendable {
    func start() async throws
    func stop() async
    func beginEnrollment() async throws -> PortholeEnrollmentInvitation
    func cancelEnrollment() async
    func peers() async -> [PortholeTrustedPeer]
    func revoke(peerID: UUID) async throws
}

extension PortholeRemoteServer: PortholeHosting {}

public protocol PortholeHostCreating: Sendable {
    func create() async throws -> any PortholeHosting
}

struct PortholeNativeHostFactory: PortholeHostCreating {
    let executor: any PortholeExecuting
    let application: @Sendable () async throws -> PortholeRemoteApplication
    let serviceName: String
    let keychainService: String

    func create() async throws -> any PortholeHosting {
        let keychain = PortholeRemoteKeychain(service: keychainService, accessGroup: nil)
        let identity = try keychain.identity(name: serviceName, at: Date())
        let trust = try PortholePeerTrust(keychain: keychain)
        return PortholeRemoteServer(
            identity: identity,
            trust: trust,
            dispatcher: PortholeRemoteDispatcher(
                executor: executor,
                application: application,
            ),
            serviceName: serviceName,
        )
    }
}
