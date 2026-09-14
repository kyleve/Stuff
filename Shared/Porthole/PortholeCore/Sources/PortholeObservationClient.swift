import Foundation

/// Typed observation controls use ordinary capability invocation, including the shared permission
/// boundary.
public struct PortholeObservationClient: Sendable {
    private let execute: @Sendable (PortholeInvocation) async throws -> PortholeValue

    public init(execute: @escaping @Sendable (PortholeInvocation) async throws -> PortholeValue) {
        self.execute = execute
    }

    public func startObservation(_ request: PortholeObservationRequest) async throws
        -> PortholeObservationReference
    {
        let result = try await execute(.init(
            id: request.id.rawValue,
            scope: request.invocation.scope,
            capabilityID: PortholeObservationCapabilities.start,
            receiver: nil,
            arguments: .object(["request": .encoding(request)]),
        ))
        let reference = try result.decode(PortholeObservationReference.self)
        guard reference == request.reference else { throw PortholeError.operationConflict }
        return reference
    }

    /// A timeout returns the current snapshot; compare its sequence before displaying another
    /// sample.
    public func readObservation(
        _ reference: PortholeObservationReference,
        afterSequence: Int64?,
        waitMilliseconds: Int,
    ) async throws -> PortholeObservationSnapshot {
        let result = try await execute(.init(
            id: UUID(),
            scope: reference.scope,
            capabilityID: PortholeObservationCapabilities.read,
            receiver: nil,
            arguments: .object([
                "observation": .encoding(reference),
                "afterSequence": afterSequence.map(PortholeValue.integer) ?? .null,
                "waitMilliseconds": .integer(Int64(waitMilliseconds)),
            ]),
        ))
        let snapshot = try result.decode(PortholeObservationSnapshot.self)
        guard snapshot.observation == reference else { throw PortholeError.operationConflict }
        return snapshot
    }

    /// Stop is idempotent and also prevents a delayed start with this identity.
    public func stopObservation(_ reference: PortholeObservationReference) async throws {
        let result = try await execute(.init(
            id: UUID(),
            scope: reference.scope,
            capabilityID: PortholeObservationCapabilities.stop,
            receiver: nil,
            arguments: .object(["observation": .encoding(reference)]),
        ))
        guard result == .null else { throw PortholeError.operationConflict }
    }
}

extension PortholeExecuting {
    public func startObservation(_ request: PortholeObservationRequest) async throws
        -> PortholeObservationReference
    {
        try await PortholeObservationClient { invocation in try await self.invoke(invocation) }
            .startObservation(request)
    }

    public func readObservation(
        _ reference: PortholeObservationReference,
        afterSequence: Int64?,
        waitMilliseconds: Int,
    ) async throws -> PortholeObservationSnapshot {
        try await PortholeObservationClient { invocation in try await self.invoke(invocation) }
            .readObservation(
                reference,
                afterSequence: afterSequence,
                waitMilliseconds: waitMilliseconds,
            )
    }

    public func stopObservation(_ reference: PortholeObservationReference) async throws {
        try await PortholeObservationClient { invocation in try await self.invoke(invocation) }
            .stopObservation(reference)
    }
}
