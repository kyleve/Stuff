import Darwin

public protocol ProcessInspecting: Sendable {
    func isRunning(processID: Int32) -> Bool
}

public struct SystemProcessInspector: ProcessInspecting {
    public init() {}

    public func isRunning(processID: Int32) -> Bool {
        if kill(processID, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
