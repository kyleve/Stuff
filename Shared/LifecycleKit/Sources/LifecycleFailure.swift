/// Carries which node failed and why, so the (terminal) failure UI can name
/// and describe it.
public struct LifecycleFailure {
    public let stepID: AnyHashable
    public let error: any Error

    public init(stepID: AnyHashable, error: any Error) {
        self.stepID = stepID
        self.error = error
    }
}
