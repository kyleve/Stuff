import Foundation
import PortholeCore

/// Registry-owned latest-value storage. Workers never mutate this state outside the registry actor.
struct PortholeObservationStore {
    struct CapturedValue {
        let invocationID: UUID
        let capturedAt: Date
        let value: PortholeValue
    }

    struct Update {
        let shouldContinue: Bool
        let releasedLeaseID: UUID?
    }

    private struct Waiter {
        let afterSequence: Int64?
        let continuation: CheckedContinuation<PortholeObservationSnapshot, any Error>
        let timeout: Task<Void, Never>
    }

    private struct Entry {
        let request: PortholeObservationRequest
        let generation: UUID
        let owner: PortholeObservationOwnerID?
        var leaseID: UUID?
        var state: PortholeObservationSnapshot.State
        var task: Task<Void, Never>?
        var waiters: [UUID: Waiter]

        var snapshot: PortholeObservationSnapshot {
            .init(observation: request.reference, state: state)
        }
    }

    private struct Identity {
        let owner: PortholeObservationOwnerID?
    }

    private var entries: [PortholeObservationReference: Entry] = [:]
    private var knownIDs: [PortholeObservationReference: Identity] = [:]
    private var waiterCount = 0
    private var closedOwners: Set<PortholeObservationOwnerID> = []
    private var closedOwnerLimitReached = false
    private static let maximumObservations = 32
    private static let maximumKnownIDs = 4096
    private static let maximumWaiters = 64
    private static let maximumSampleBytes = 1_048_576

    @discardableResult
    func validateStart(
        _ request: PortholeObservationRequest,
        owner: PortholeObservationOwnerID?,
    ) throws -> Bool {
        try authorize(request.reference, owner: owner)
        if let owner {
            guard !closedOwners.contains(owner) else { throw PortholeError.observationEnded }
            guard !closedOwnerLimitReached else {
                throw PortholeError
                    .observationCapacityExceeded(
                        "The closed-session limit was reached. End all application scopes before opening another remote observation.",
                    )
            }
        }
        guard (1000 ... 60000).contains(request.intervalMilliseconds) else {
            throw PortholeError
                .invalidArguments(
                    "Observation interval must be from 1000 through 60000 milliseconds.",
                )
        }
        if let entry = entries[request.reference] {
            guard entry.request == request else { throw PortholeError.operationConflict }
            return false
        }
        guard knownIDs[request.reference] == nil else { throw PortholeError.observationEnded }
        guard entries.count < Self.maximumObservations else {
            throw PortholeError
                .observationCapacityExceeded(
                    "Stop an observation before starting another. The limit is 32.",
                )
        }
        try validateNewIdentity(request.reference)
        return true
    }

    mutating func start(
        _ request: PortholeObservationRequest,
        generation: UUID,
        owner: PortholeObservationOwnerID?,
        leaseID: UUID,
        execute: @escaping @Sendable (PortholeInvocation) async throws -> PortholeValue,
        report: @escaping @Sendable (Result<CapturedValue, any Error>) async -> Bool,
    ) {
        knownIDs[request.reference] = Identity(owner: owner)
        let task = Task {
            do {
                while !Task.isCancelled {
                    let invocation = PortholeInvocation(
                        id: UUID(),
                        scope: request.invocation.scope,
                        capabilityID: request.invocation.capabilityID,
                        receiver: request.invocation.receiver,
                        arguments: request.invocation.arguments,
                    )
                    let value = try await execute(invocation)
                    try Task.checkCancellation()
                    guard try value.data().count <= Self.maximumSampleBytes else {
                        throw PortholeError
                            .observationCapacityExceeded(
                                "A sample exceeds one MiB. Select a smaller result or page.",
                            )
                    }
                    guard await report(.success(CapturedValue(
                        invocationID: invocation.id,
                        capturedAt: Date(),
                        value: value,
                    ))) else { return }
                    try await Task.sleep(for: .milliseconds(request.intervalMilliseconds))
                }
            } catch {
                if error is CancellationError, Task.isCancelled { return }
                _ = await report(.failure(error))
            }
        }
        entries[request.reference] = Entry(
            request: request,
            generation: generation,
            owner: owner,
            leaseID: leaseID,
            state: .waiting,
            task: task,
            waiters: [:],
        )
    }

    mutating func publish(
        _ result: Result<CapturedValue, any Error>,
        for reference: PortholeObservationReference,
        generation: UUID,
    ) -> Update {
        guard var entry = entries[reference], entry.generation == generation else {
            return Update(shouldContinue: false, releasedLeaseID: nil)
        }
        let lastSample = entry.snapshot.latestSample
        let releasedLeaseID: UUID?
        let shouldContinue: Bool
        switch result {
            case let .success(captured):
                let sequence = (lastSample?.sequence ?? 0).addingReportingOverflow(1)
                if sequence.overflow {
                    entry.state = .failed(
                        message: "The observation sequence limit was reached.",
                        lastSample: lastSample,
                    )
                    shouldContinue = false
                } else {
                    entry.state = .sample(.init(
                        sequence: sequence.partialValue,
                        invocationID: captured.invocationID,
                        capturedAt: captured.capturedAt,
                        value: captured.value,
                    ))
                    shouldContinue = true
                }
            case let .failure(error):
                entry.state = .failed(message: error.localizedDescription, lastSample: lastSample)
                shouldContinue = false
        }
        if shouldContinue {
            releasedLeaseID = nil
        } else {
            releasedLeaseID = entry.leaseID
            entry.leaseID = nil
            entry.task = nil
        }
        for (waiterID, waiter) in entry.waiters where isReady(
            entry.state,
            afterSequence: waiter.afterSequence,
        ) {
            entry.waiters[waiterID] = nil
            waiterCount -= 1
            waiter.timeout.cancel()
            waiter.continuation.resume(returning: entry.snapshot)
        }
        entries[reference] = entry
        return Update(shouldContinue: shouldContinue, releasedLeaseID: releasedLeaseID)
    }

    func snapshotIfReady(
        _ reference: PortholeObservationReference,
        afterSequence: Int64?,
        waitMilliseconds: Int,
    ) throws -> PortholeObservationSnapshot? {
        guard afterSequence.map({ $0 >= 0 }) ?? true,
              (0 ... 10000).contains(waitMilliseconds)
        else {
            throw PortholeError
                .invalidArguments(
                    "afterSequence must be nonnegative or null; waitMilliseconds must be from 0 through 10000.",
                )
        }
        guard let entry = entries[reference] else { throw PortholeError.observationEnded }
        return waitMilliseconds == 0 || isReady(entry.state, afterSequence: afterSequence) ? entry
            .snapshot : nil
    }

    mutating func wait(
        for reference: PortholeObservationReference,
        waiterID: UUID,
        afterSequence: Int64?,
        waitMilliseconds: Int,
        continuation: CheckedContinuation<PortholeObservationSnapshot, any Error>,
        expired: @escaping @Sendable ((any Error)?) async -> Void,
    ) throws {
        if let snapshot = try snapshotIfReady(
            reference,
            afterSequence: afterSequence,
            waitMilliseconds: waitMilliseconds,
        ) {
            continuation.resume(returning: snapshot)
            return
        }
        guard waiterCount < Self.maximumWaiters else {
            throw PortholeError
                .observationCapacityExceeded(
                    "Finish a pending observation read before starting another. The limit is 64.",
                )
        }
        guard entries[reference]?.waiters[waiterID] == nil
        else { throw PortholeError.operationConflict }
        let timeout = Task {
            do { try await Task.sleep(for: .milliseconds(waitMilliseconds)); await expired(nil) }
            catch is CancellationError {
            /* A sample, stop, or caller cancellation completed this read. */ } catch {
                await expired(error)
            }
        }
        entries[reference]?.waiters[waiterID] = Waiter(
            afterSequence: afterSequence,
            continuation: continuation,
            timeout: timeout,
        )
        waiterCount += 1
    }

    mutating func finishRead(waiterID: UUID, error: (any Error)?) {
        guard let reference = entries.first(where: { $0.value.waiters[waiterID] != nil })?.key,
              var entry = entries[reference],
              let waiter = entry.waiters.removeValue(forKey: waiterID) else { return }
        entries[reference] = entry
        waiterCount -= 1
        waiter.timeout.cancel()
        if let error { waiter.continuation.resume(throwing: error) }
        else { waiter.continuation.resume(returning: entry.snapshot) }
    }

    func authorize(
        _ reference: PortholeObservationReference,
        owner: PortholeObservationOwnerID?,
    ) throws {
        if let owner, let identity = knownIDs[reference], identity.owner != owner {
            throw PortholeError.operationConflict
        }
    }

    mutating func stop(
        _ reference: PortholeObservationReference,
        owner: PortholeObservationOwnerID?,
    ) throws -> UUID? {
        try authorize(reference, owner: owner)
        try validateNewIdentity(reference)
        if knownIDs[reference] == nil { knownIDs[reference] = Identity(owner: owner) }
        return remove(reference, error: PortholeError.observationEnded)
    }

    mutating func disable() -> [UUID] {
        Array(entries.keys).compactMap { remove($0, error: PortholeError.disabled) }
    }

    mutating func stop(ownedBy owner: PortholeObservationOwnerID) -> [UUID] {
        if closedOwners.count < Self.maximumKnownIDs || closedOwners.contains(owner) {
            closedOwners.insert(owner)
        } else {
            closedOwnerLimitReached = true
        }
        return entries.filter { $0.value.owner == owner }.map(\.key).compactMap {
            remove($0, error: PortholeError.observationEnded)
        }
    }

    mutating func clearEndedOwners() {
        closedOwners.removeAll()
        closedOwnerLimitReached = false
    }

    mutating func invalidate(_ scope: PortholeScopeToken) -> [UUID] {
        let leases = entries.keys.filter { $0.scope == scope }.compactMap { remove(
            $0,
            error: PortholeError.staleScope,
        ) }
        knownIDs = knownIDs.filter { $0.key.scope != scope }
        return leases
    }

    private mutating func remove(
        _ reference: PortholeObservationReference,
        error: any Error,
    ) -> UUID? {
        guard let entry = entries.removeValue(forKey: reference) else { return nil }
        entry.task?.cancel()
        for waiter in entry.waiters.values {
            waiter.timeout.cancel()
            waiter.continuation.resume(throwing: error)
        }
        waiterCount -= entry.waiters.count
        return entry.leaseID
    }

    private func validateNewIdentity(_ reference: PortholeObservationReference) throws {
        guard knownIDs[reference] != nil || knownIDs.count < Self.maximumKnownIDs else {
            throw PortholeError
                .observationCapacityExceeded(
                    "This scope has used 4096 observation identities. Replace the application scope to continue.",
                )
        }
    }

    private func isReady(
        _ state: PortholeObservationSnapshot.State,
        afterSequence: Int64?,
    ) -> Bool {
        switch state {
            case .waiting: false
            case let .sample(sample): afterSequence == nil || sample.sequence > (afterSequence ?? 0)
            case .failed: true
        }
    }
}
