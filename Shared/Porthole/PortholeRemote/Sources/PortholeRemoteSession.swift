import Foundation
import os
import PortholeCore

/// An authenticated connection owns its runtime observations, including starts with lost replies.
actor PortholeRemoteSession {
    private enum Observation {
        case active(PortholeObservationReference)
        case stopped(PortholeObservationReference)

        var reference: PortholeObservationReference {
            switch self {
                case let .active(reference), let .stopped(reference): reference
            }
        }
    }

    private let dispatcher: PortholeRemoteDispatcher
    private let executor: any PortholeExecuting
    private let ownerID = PortholeObservationOwnerID(rawValue: UUID())
    private let log = Logger(subsystem: "com.stuff.porthole", category: "RemoteObservations")
    private var observations: [PortholeObservationID: Observation] = [:]
    private var closed = false

    init(dispatcher: PortholeRemoteDispatcher, executor: any PortholeExecuting) {
        self.dispatcher = dispatcher
        self.executor = executor
    }

    func respond(to request: PortholeRemoteRequest) async -> PortholeRemoteResponse {
        do {
            guard !closed else { throw PortholeRemoteError.disconnected }
            guard request.version == 1 else { throw PortholeRemoteError.invalidMessage }
            if case let .invoke(invocation) = request.operation {
                try track(invocation)
            }
            let response = await PortholeObservationOwnership.$current.withValue(ownerID) {
                await dispatcher.respond(to: request)
            }
            if case let .invoke(invocation) = request.operation,
               !(executor is any PortholeObservationOwning),
               invocation.capabilityID == PortholeObservationCapabilities.stop,
               case .value = response.result,
               let value = invocation.arguments["observation"]
            {
                let reference = try value.decode(PortholeObservationReference.self)
                if !closed { observations[reference.id] = .stopped(reference) }
            }
            return response
        } catch {
            return PortholeRemoteResponse(requestID: request.requestID, result: .failure(
                code: "invalid_observation_session",
                message: error.localizedDescription,
            ))
        }
    }

    func close() async {
        guard !closed else { return }
        closed = true
        let pending = observations.values
            .compactMap { observation -> PortholeObservationReference? in
                switch observation {
                    case let .active(reference): reference
                    case .stopped: nil
                }
            }
        observations.removeAll()
        if let owner = executor as? any PortholeObservationOwning {
            await owner.stopObservations(ownedBy: ownerID)
            return
        }
        for reference in pending {
            do { try await executor.stopObservation(reference) }
            catch PortholeError.staleScope {
                // Scope replacement already invalidated this connection's observation.
            } catch {
                log
                    .error(
                        "Disconnected observation cleanup failed: \(error.localizedDescription, privacy: .public)",
                    )
            }
        }
    }

    private func track(_ invocation: PortholeInvocation) throws {
        switch invocation.capabilityID {
            case PortholeObservationCapabilities.start:
                guard let value = invocation.arguments["request"]
                else { throw PortholeRemoteError.invalidMessage }
                let request = try value.decode(PortholeObservationRequest.self)
                let reference = PortholeObservationReference(
                    id: request.id,
                    scope: request.invocation.scope,
                )
                guard invocation.scope == reference.scope
                else { throw PortholeRemoteError.invalidMessage }
                // The runtime owns its identity ledger, including nested starts and stopped IDs.
                guard !(executor is any PortholeObservationOwning) else { return }
                guard
                    observations[reference.id] == nil || observations[reference.id]?
                    .reference == reference,
                    observations[reference.id] != nil || observations.count < 4096
                else { throw PortholeRemoteError.invalidMessage }
                // Register before suspension: disconnect must also stop an uncertain start.
                if observations[reference.id] ==
                    nil { observations[reference.id] = .active(reference) }
            case PortholeObservationCapabilities.read, PortholeObservationCapabilities.stop:
                guard let value = invocation.arguments["observation"]
                else { throw PortholeRemoteError.invalidMessage }
                let reference = try value.decode(PortholeObservationReference.self)
                guard invocation.scope == reference.scope
                else { throw PortholeRemoteError.invalidMessage }
                if !(executor is any PortholeObservationOwning),
                   observations[reference.id]?.reference != reference
                {
                    throw PortholeRemoteError.invalidMessage
                }
            // Retain stopped references until close, so retries and delayed starts keep ownership.
            default: break
        }
    }
}
