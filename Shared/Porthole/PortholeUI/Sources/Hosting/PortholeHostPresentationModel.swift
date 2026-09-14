import Foundation
import Observation
import PortholeCore
import PortholeRemote

/// Remote activation is independent from local debugging and does no credential work at init.
@MainActor @Observable
public final class PortholeHostPresentationModel {
    enum State {
        case disabled
        case creating(UUID)
        case starting(UUID, any PortholeHosting)
        case active(PortholeHostedSession)
        case failed(String)
    }

    private let factory: any PortholeHostCreating
    private(set) var state: State = .disabled

    public init(
        executor: any PortholeExecuting,
        application: @escaping @Sendable () async throws -> PortholeRemoteApplication,
        serviceName: String,
        keychainService: String,
    ) {
        factory = PortholeNativeHostFactory(
            executor: executor,
            application: application,
            serviceName: serviceName,
            keychainService: keychainService,
        )
    }

    public init(factory: any PortholeHostCreating) {
        self.factory = factory
    }

    var activeSession: PortholeHostedSession? {
        if case let .active(session) = state { session } else { nil }
    }

    var isStarting: Bool {
        switch state {
            case .creating, .starting: true
            case .disabled, .active, .failed: false
        }
    }

    public func enable() async {
        guard !isStarting, activeSession == nil else { return }
        let operationID = UUID()
        state = .creating(operationID)
        do {
            let server = try await factory.create()
            guard case .creating(operationID) = state else { await server.stop(); return }
            state = .starting(operationID, server)
            do {
                try await server.start()
                try Task.checkCancellation()
                guard case .starting(operationID, _) = state else { await server.stop(); return }
                let session = PortholeHostedSession(server: server)
                await session.refresh()
                guard case .starting(operationID, _) = state else { await server.stop(); return }
                state = .active(session)
            } catch {
                await server.stop()
                throw error
            }
        } catch is CancellationError {
            if matches(operationID) { state = .disabled }
        } catch {
            PortholeUILog.failures
                .error("Remote activation failed: \(String(describing: error), privacy: .private)")
            if matches(operationID) { state = .failed(error.localizedDescription) }
        }
    }

    public func disable() async {
        let previous = state
        state = .disabled
        switch previous {
            case let .starting(_, server): await server.stop()
            case let .active(session):
                session.clearInvitation()
                await session.server.stop()
            case .disabled, .creating, .failed: break
        }
    }

    private func matches(_ operationID: UUID) -> Bool {
        switch state {
            case let .creating(current), let .starting(current, _): current == operationID
            case .disabled, .active, .failed: false
        }
    }
}
