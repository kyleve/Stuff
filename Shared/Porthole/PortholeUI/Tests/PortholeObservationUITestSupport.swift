import Foundation
import PortholeRuntime
@testable import PortholeUI

/// Deliberately lets cancelled requests finish so tests can deliver old connection callbacks.
@MainActor
final class PortholeObservationUITestExecutor {
    struct Read {
        let observation: PortholeObservationReference
        let afterSequence: Int64?
        let waitMilliseconds: Int
    }

    var holdStarts = false
    var stopFailures = 0
    private(set) var starts: [PortholeObservationRequest] = []
    private(set) var reads: [Read] = []
    private(set) var stops: [PortholeObservationReference] = []
    private(set) var completedReads: Set<PortholeObservationID> = []
    private var pendingStarts: [PortholeObservationID: CheckedContinuation<Void, Never>] = [:]
    private var pendingReads: [PortholeObservationID: CheckedContinuation<
        PortholeObservationSnapshot,
        any Error
    >] = [:]

    func execute(_ invocation: PortholeInvocation) async throws -> PortholeValue {
        switch invocation.capabilityID {
            case PortholeObservationCapabilities.start:
                guard let value = invocation.arguments["request"] else {
                    throw PortholeError.invalidArguments("Missing observation request")
                }
                let request = try value.decode(PortholeObservationRequest.self)
                starts.append(request)
                if holdStarts {
                    await withCheckedContinuation { pendingStarts[request.id] = $0 }
                }
                return try .encoding(PortholeObservationReference(
                    id: request.id,
                    scope: request.invocation.scope,
                ))
            case PortholeObservationCapabilities.read:
                guard let value = invocation.arguments["observation"] else {
                    throw PortholeError.invalidArguments("Missing observation reference")
                }
                let observation = try value.decode(PortholeObservationReference.self)
                let read = try Read(
                    observation: observation,
                    afterSequence: invocation.arguments["afterSequence"]?
                        .decode(Int64?.self) ?? nil,
                    waitMilliseconds: invocation.arguments["waitMilliseconds"]?
                        .decode(Int.self) ?? 0,
                )
                reads.append(read)
                let snapshot = try await withCheckedThrowingContinuation {
                    pendingReads[observation.id] = $0
                }
                completedReads.insert(observation.id)
                return try .encoding(snapshot)
            case PortholeObservationCapabilities.stop:
                guard let value = invocation.arguments["observation"] else {
                    throw PortholeError.invalidArguments("Missing observation reference")
                }
                let observation = try value.decode(PortholeObservationReference.self)
                stops.append(observation)
                if stopFailures > 0 {
                    stopFailures -= 1
                    throw PortholeError.operationFailed("The device is offline")
                }
                return .null
            default: throw PortholeError.unsupported("Unexpected fixture invocation")
        }
    }

    func releaseStart(_ observationID: PortholeObservationID) {
        pendingStarts.removeValue(forKey: observationID)?.resume()
    }

    func hasPendingRead(_ observationID: PortholeObservationID) -> Bool {
        pendingReads[observationID] != nil
    }

    func deliver(_ snapshot: PortholeObservationSnapshot) {
        pendingReads.removeValue(forKey: snapshot.observation.id)?.resume(returning: snapshot)
    }

    func finishPendingCalls() {
        let starts = pendingStarts.values
        pendingStarts.removeAll()
        for continuation in starts {
            continuation.resume()
        }
        let reads = pendingReads.values
        pendingReads.removeAll()
        for continuation in reads {
            continuation.resume(throwing: CancellationError())
        }
    }
}

enum PortholeObservationUITestSupport {
    static func invocation(scope: PortholeScopeToken) -> PortholeInvocation {
        .init(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "fixture.read"),
            receiver: nil,
            arguments: .object(["value": .string("original")]),
        )
    }

    static func snapshot(
        reference: PortholeObservationReference,
        sequence: Int64,
        value: PortholeValue,
    ) -> PortholeObservationSnapshot {
        .init(observation: reference, state: .sample(.init(
            sequence: sequence,
            invocationID: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            value: value,
        )))
    }

    @MainActor static func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        return predicate()
    }
}
