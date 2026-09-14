import Foundation
import Observation
import PortholeCore
import PortholeRemote

/// Native credentials stay in this client controller; debugger values contain only the remote
/// application's evidence.
@MainActor @Observable
public final class PortholeRemotePresentationModel {
    struct Session {
        let id: UUID
        let client: PortholeRemoteClient
        let application: PortholeRemoteApplication
    }

    enum ConnectionState { case idle, connecting(UUID), connected(Session), failed(String) }
    struct ScopeSnapshot {
        let capabilities: [PortholeCapability]
        let contexts: [PortholeContext]?
        let objects: [PortholeObjectReference]?
    }

    enum ScopeState { case idle, loading(PortholeScopeToken), loaded(
        PortholeScopeToken,
        ScopeSnapshot,
    ), failed(String) }
    enum PairingState { case idle, pairing(UUID), paired(String), failed(String) }

    let clientName: String
    private let connector: any PortholeRemoteConnecting
    private(set) var connection: ConnectionState = .idle
    private(set) var scopeState: ScopeState = .idle
    private(set) var pairing: PairingState = .idle
    private(set) var servers: [PortholePairedServer] = []
    private(set) var discovered: [PortholeDiscoveredApplication] = []
    private(set) var discoveryError: String?
    private(set) var savedServersError: String?
    var invitation = ""
    var search = ""

    public init(keychain: PortholeRemoteKeychain, clientName: String) {
        connector = PortholeRemoteConnector(keychain: keychain, clientName: clientName)
        self.clientName = clientName
    }

    public init(connector: any PortholeRemoteConnecting, clientName: String) {
        self.connector = connector
        self.clientName = clientName
    }

    func loadServers() async {
        do { servers = try await connector.pairedServers(); savedServersError = nil }
        catch {
            PortholeUILog.failures
                .error("Remote server list failed: \(String(describing: error), privacy: .private)")
            savedServersError = error.localizedDescription
        }
    }

    func discover() async {
        do {
            for try await applications in connector.discoveredApplications() {
                try Task.checkCancellation()
                discovered = applications
                discoveryError = nil
            }
        } catch is CancellationError { /* Discovery follows this view's lifetime. */ }
        catch {
            PortholeUILog.failures
                .error("Remote discovery failed: \(String(describing: error), privacy: .private)")
            discoveryError = error.localizedDescription
        }
    }

    func enroll() async {
        guard case .pairing = pairing else { await performEnrollment(); return }
    }

    private func performEnrollment() async {
        let requestID = UUID()
        pairing = .pairing(requestID)
        do {
            let invitation = try PortholeEnrollmentInvitation
                .decode(invitation.trimmingCharacters(in: .whitespacesAndNewlines))
            self.invitation = ""
            let server = try await connector.enroll(invitation: invitation, clientName: clientName)
            try Task.checkCancellation()
            guard case .pairing(requestID) = pairing else { return }
            pairing = .paired(server.serviceName)
            await loadServers()
        } catch is CancellationError { if case .pairing(requestID) = pairing { pairing = .idle } }
        catch {
            PortholeUILog.failures
                .error("Remote enrollment failed: \(String(describing: error), privacy: .private)")
            if case .pairing(requestID) = pairing { pairing = .failed(error.localizedDescription) }
        }
    }

    func connect(server: PortholePairedServer) async {
        await disconnect()
        let requestID = UUID()
        connection = .connecting(requestID)
        do {
            let client = try await connector.connect(server: server)
            do {
                let application = try await client.application()
                try Task.checkCancellation()
                guard case .connecting(requestID) = connection else { await client.close(); return }
                connection = .connected(Session(
                    id: requestID,
                    client: client,
                    application: application,
                ))
            } catch { await client.close(); throw error }
        } catch is CancellationError {
            if case .connecting(requestID) = connection { connection = .idle }
        } catch {
            PortholeUILog.failures
                .error("Remote connection failed: \(String(describing: error), privacy: .private)")
            if case .connecting(requestID) = connection {
                connection = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() async {
        let previous = connection
        connection = .idle
        scopeState = .idle
        if case let .connected(session) = previous { await session.client.close() }
    }

    func select(scope: PortholeScopeToken) async {
        guard case let .connected(session) = connection else { return }
        scopeState = .loading(scope)
        do {
            let capabilities = try await session.client.capabilities(in: scope)
            let contexts: [PortholeContext]? = try await query(
                "porthole.contexts",
                in: scope,
                capabilities: capabilities,
                client: session.client,
            )
            let objects: [PortholeObjectReference]? = try await query(
                "porthole.objects",
                in: scope,
                capabilities: capabilities,
                client: session.client,
            )
            try Task.checkCancellation()
            guard case let .connected(current) = connection, current.id == session.id,
                  case .loading(scope) = scopeState else { return }
            scopeState = .loaded(
                scope,
                ScopeSnapshot(capabilities: capabilities, contexts: contexts, objects: objects),
            )
        } catch is CancellationError { if case .loading(scope) = scopeState { scopeState = .idle } }
        catch {
            PortholeUILog.failures
                .error("Remote scope load failed: \(String(describing: error), privacy: .private)")
            if case .loading(scope) = scopeState { scopeState = .failed(error.localizedDescription)
            }
        }
    }

    func execute(_ invocation: PortholeInvocation) async throws -> PortholeValue {
        guard case let .connected(session) = connection
        else { throw PortholeRemoteError.disconnected }
        return try await session.client.invoke(invocation)
    }

    var evidenceNavigation: PortholeEvidenceNavigation? {
        guard case let .connected(session) = connection else { return nil }
        let execute: @MainActor (PortholeInvocation) async throws
            -> PortholeValue = { [weak self] invocation in
                guard let self, case let .connected(current) = connection, current.id == session.id
                else { throw PortholeRemoteError.disconnected }
                let result = try await session.client.invoke(invocation)
                try Task.checkCancellation()
                guard case let .connected(current) = connection, current.id == session.id
                else { throw PortholeRemoteError.disconnected }
                return result
            }
        let reader = PortholeRemoteEvidenceReader(catalog: { [weak self] scope in
            guard let self, case let .connected(current) = connection, current.id == session.id
            else { throw PortholeRemoteError.disconnected }
            let result = try await session.client.capabilities(in: scope)
            try Task.checkCancellation()
            guard case let .connected(current) = connection, current.id == session.id
            else { throw PortholeRemoteError.disconnected }
            return result
        }, invoke: execute)
        return PortholeEvidenceNavigation(reader: reader, execute: execute)
    }

    private func query<T: Decodable>(
        _ name: String,
        in scope: PortholeScopeToken,
        capabilities: [PortholeCapability],
        client: PortholeRemoteClient,
    ) async throws -> T? {
        let capabilityID = PortholeSymbolID(rawValue: name)
        guard capabilities
            .contains(where: {
                $0.id == capabilityID && $0.effect == .read && $0.availability == .callable
            })
        else { return nil }
        let result = try await client.invoke(.init(
            id: UUID(),
            scope: scope,
            capabilityID: capabilityID,
            receiver: nil,
            arguments: .object([:]),
        ))
        return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(result))
    }
}
