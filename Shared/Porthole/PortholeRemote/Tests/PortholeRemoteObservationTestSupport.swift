import Foundation
import PortholeCore
@testable import PortholeRemote

/// A controlled shared executor supplies samples without timing-dependent transport tests.
actor PortholeRemoteObservationTestExecutor: PortholeExecuting, PortholeObservationOwning {
    private struct ProgressWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct PendingRead {
        let reference: PortholeObservationReference
        let continuation: CheckedContinuation<PortholeValue, any Error>
    }

    let effect: PortholeEffect
    let sampleCount: Int64
    let delaysStart: Bool
    var starts: [PortholeObservationRequest] = []
    var stops: [PortholeObservationReference] = []
    var reads = 0
    var directInvocations = 0
    var owners: [PortholeObservationOwnerID] = []
    var endedOwners: [PortholeObservationOwnerID] = []
    private var observationOwners: [PortholeObservationReference: PortholeObservationOwnerID] = [:]
    private var sequence: Int64 = 0
    private var pendingReads: [PendingRead] = []
    private var startWaiters: [ProgressWaiter] = []
    private var readWaiters: [ProgressWaiter] = []
    private var stopWaiters: [ProgressWaiter] = []
    private var delayedStart: CheckedContinuation<Void, Never>?

    init(effect: PortholeEffect, sampleCount: Int64, delaysStart: Bool) {
        self.effect = effect
        self.sampleCount = sampleCount
        self.delaysStart = delaysStart
    }

    func capabilities(in _: PortholeScopeToken) -> [PortholeCapability] {
        [PortholeRemoteTestSupport.capability(effect: effect)]
    }

    func invoke(_ invocation: PortholeInvocation) async throws -> PortholeValue {
        if let owner = PortholeObservationOwnership.current { owners.append(owner) }
        switch invocation.capabilityID {
            case PortholeObservationCapabilities.start:
                guard let value = invocation.arguments["request"]
                else { throw PortholeRemoteError.invalidMessage }
                let request = try value.decode(PortholeObservationRequest.self)
                let reference = request.reference
                try validateOwner(reference, allowUnknown: true)
                starts.append(request)
                resumeProgress(&startWaiters, count: starts.count)
                guard effect == .read
                else {
                    throw PortholeError.invalidArguments("Only classified reads can be observed.")
                }
                if let owner = PortholeObservationOwnership.current {
                    guard !endedOwners.contains(owner) else { throw PortholeError.observationEnded }
                    observationOwners[reference] = owner
                }
                if delaysStart {
                    await withCheckedContinuation { delayedStart = $0 }
                }
                if stops.contains(reference) { throw PortholeError.observationEnded }
                return try .encoding(reference)
            case PortholeObservationCapabilities.read:
                guard let value = invocation.arguments["observation"]
                else { throw PortholeRemoteError.invalidMessage }
                let reference = try value.decode(PortholeObservationReference.self)
                try validateOwner(reference, allowUnknown: false)
                if stops.contains(reference) { throw PortholeError.observationEnded }
                reads += 1
                resumeProgress(&readWaiters, count: reads)
                if sequence < sampleCount {
                    sequence += 1
                    return try .encoding(PortholeObservationSnapshot(
                        observation: reference,
                        state: .sample(.init(
                            sequence: sequence,
                            invocationID: UUID(),
                            capturedAt: Date(timeIntervalSince1970: TimeInterval(sequence)),
                            value: .integer(sequence),
                        )),
                    ))
                }
                return try await withCheckedThrowingContinuation { continuation in
                    pendingReads.append(PendingRead(
                        reference: reference,
                        continuation: continuation,
                    ))
                }
            case PortholeObservationCapabilities.stop:
                guard let value = invocation.arguments["observation"]
                else { throw PortholeRemoteError.invalidMessage }
                let reference = try value.decode(PortholeObservationReference.self)
                try validateOwner(reference, allowUnknown: true)
                stop(reference)
                return .null
            default:
                directInvocations += 1
                if invocation.capabilityID.rawValue == "test.nested-start" {
                    return try await .encoding(startObservation(.init(
                        id: .init(rawValue: UUID()),
                        invocation: PortholeRemoteTestSupport.invocation(),
                        intervalMilliseconds: 1000,
                    )))
                }
                return .string("direct invocation")
        }
    }

    func stopObservations(ownedBy owner: PortholeObservationOwnerID) {
        endedOwners.append(owner)
        for reference in observationOwners.filter({ $0.value == owner }).map(\.key) {
            stop(reference)
        }
    }

    private func stop(_ reference: PortholeObservationReference) {
        if !stops.contains(reference) { stops.append(reference) }
        resumeProgress(&stopWaiters, count: stops.count)
        let pending = pendingReads.filter { $0.reference == reference }
        pendingReads.removeAll { $0.reference == reference }
        for read in pending {
            read.continuation.resume(throwing: PortholeError.observationEnded)
        }
    }

    private func validateOwner(
        _ reference: PortholeObservationReference,
        allowUnknown: Bool,
    ) throws {
        guard let owner = PortholeObservationOwnership.current else { return }
        if let existing = observationOwners[reference] {
            guard existing == owner else { throw PortholeError.observationEnded }
        } else {
            guard allowUnknown else { throw PortholeError.observationEnded }
            observationOwners[reference] = owner
        }
    }

    func releaseStart() {
        delayedStart?.resume()
        delayedStart = nil
    }

    func releaseReads() throws {
        let pending = pendingReads
        pendingReads.removeAll()
        for read in pending {
            try read.continuation.resume(returning: .encoding(PortholeObservationSnapshot(
                observation: read.reference,
                state: .waiting,
            )))
        }
    }

    func releaseReadsWithLastSample() throws {
        let pending = pendingReads
        pendingReads.removeAll()
        for read in pending {
            try read.continuation.resume(returning: .encoding(PortholeObservationSnapshot(
                observation: read.reference,
                state: .sample(.init(
                    sequence: sequence,
                    invocationID: UUID(),
                    capturedAt: Date(timeIntervalSince1970: TimeInterval(sequence)),
                    value: .integer(sequence),
                )),
            )))
        }
    }

    func waitForStarts(_ count: Int) async {
        if starts.count >= count { return }
        await withCheckedContinuation { startWaiters.append(ProgressWaiter(
            count: count,
            continuation: $0,
        )) }
    }

    func waitForReads(_ count: Int) async {
        if reads >= count { return }
        await withCheckedContinuation { readWaiters.append(ProgressWaiter(
            count: count,
            continuation: $0,
        )) }
    }

    func waitForStops(_ count: Int) async {
        if stops.count >= count { return }
        await withCheckedContinuation { stopWaiters.append(ProgressWaiter(
            count: count,
            continuation: $0,
        )) }
    }

    private func resumeProgress(_ waiters: inout [ProgressWaiter], count: Int) {
        let ready = waiters.filter { $0.count <= count }
        waiters.removeAll { $0.count <= count }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}
