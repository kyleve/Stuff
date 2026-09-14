import Foundation

/// A client chooses this identity before starting an observation, so an uncertain start can be
/// stopped.
public struct PortholeObservationID: Sendable, Hashable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct PortholeObservationReference: Sendable, Hashable, Codable {
    public let id: PortholeObservationID
    public let scope: PortholeScopeToken

    public init(id: PortholeObservationID, scope: PortholeScopeToken) {
        self.id = id
        self.scope = scope
    }
}

/// Repeated reads keep the original scope and arguments. Each sample receives a fresh invocation
/// identity.
public struct PortholeObservationRequest: Sendable, Equatable, Codable {
    public let id: PortholeObservationID
    public let invocation: PortholeInvocation
    public let intervalMilliseconds: Int

    public init(
        id: PortholeObservationID,
        invocation: PortholeInvocation,
        intervalMilliseconds: Int,
    ) {
        self.id = id
        self.invocation = invocation
        self.intervalMilliseconds = intervalMilliseconds
    }

    public var reference: PortholeObservationReference {
        .init(id: id, scope: invocation.scope)
    }
}

public struct PortholeObservationSample: Sendable, Equatable, Codable {
    public let sequence: Int64
    public let invocationID: UUID
    public let capturedAt: Date
    public let value: PortholeValue

    public init(sequence: Int64, invocationID: UUID, capturedAt: Date, value: PortholeValue) {
        self.sequence = sequence
        self.invocationID = invocationID
        self.capturedAt = capturedAt
        self.value = value
    }
}

/// Only the latest sample is retained. A sequence gap does not imply recorded intermediate
/// evidence.
public struct PortholeObservationSnapshot: Sendable, Equatable, Codable {
    public enum State: Sendable, Equatable, Codable {
        case waiting
        case sample(PortholeObservationSample)
        case failed(message: String, lastSample: PortholeObservationSample?)
    }

    public let observation: PortholeObservationReference
    public let state: State

    public init(observation: PortholeObservationReference, state: State) {
        self.observation = observation
        self.state = state
    }

    public var latestSample: PortholeObservationSample? {
        switch state {
            case .waiting: nil
            case let .sample(sample): sample
            case let .failed(_, lastSample): lastSample
        }
    }
}

public enum PortholeObservationCapabilities {
    public static let start = PortholeSymbolID(rawValue: "porthole.observations.start")
    public static let read = PortholeSymbolID(rawValue: "porthole.observations.read")
    public static let stop = PortholeSymbolID(rawValue: "porthole.observations.stop")
}
