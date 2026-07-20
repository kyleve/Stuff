/// Carries which node failed and why, so the failure UI can describe it and
/// the runner can retry from that node.
public struct LifecycleFailure {
    public let stepID: AnyHashable
    public let error: any Error

    public init(stepID: AnyHashable, error: any Error) {
        self.stepID = stepID
        self.error = error
    }
}
