import Foundation

public enum PortholeError: Error, Sendable, Equatable, LocalizedError {
    case disabled
    case staleScope
    case unknownCapability(PortholeSymbolID)
    case unsupported(String)
    case invalidArguments(String)
    case unknownObject
    case wrongObjectType(String)
    case approvalRequired(PortholeActionProposal)
    case operationConflict
    case operationInProgress
    case uncertainOperation
    case operationFailed(String)
    case capacityExceeded
    case observationEnded
    case observationCapacityExceeded(String)

    public var errorDescription: String? {
        switch self {
            case .disabled: "Porthole is disabled."
            case .staleScope: "This application scope is no longer active. Capture the current context."
            case let .unknownCapability(symbol): "The capability is unavailable: \(symbol.rawValue)."
            case let .unsupported(reason): "This operation is unsupported: \(reason)."
            case let .invalidArguments(reason): "Invalid arguments: \(reason)."
            case .unknownObject: "The object reference has expired or is unavailable."
            case let .wrongObjectType(type): "The object is not a \(type)."
            case let .approvalRequired(proposal): "Approve \(proposal.capability.name) before it runs."
            case .operationConflict: "This operation identity belongs to another request."
            case .operationInProgress: "This operation is already running."
            case .uncertainOperation: "This operation may have completed. Inspect its effects before starting another operation."
            case let .operationFailed(message): "The operation failed: \(message)"
            case .capacityExceeded: "The debugger reached its object limit. Release an investigation before continuing."
            case .observationEnded: "This observation has ended. Start a new observation to continue."
            case let .observationCapacityExceeded(reason): "The observation limit was reached. \(reason)"
        }
    }
}
