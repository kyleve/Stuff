/// An observable failure from resolving or persisting a feature flag.
public struct FlaggerFailure: Error, Equatable, Sendable {
    public enum Operation: String, Sendable {
        case read
        case write
        case reset
    }

    public let flagID: FlagID?
    public let operation: Operation
    public let message: String

    init(flagID: FlagID?, operation: Operation, error: any Error) {
        self.flagID = flagID
        self.operation = operation
        message = String(describing: error)
    }
}
