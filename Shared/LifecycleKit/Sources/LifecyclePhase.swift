/// The single observable value the host renders. The runner publishes a
/// `LifecyclePhase`; `LifecycleContainer` maps each case to UI.
public enum LifecyclePhase {
    /// Before any presenting step — show the splash.
    case launching
    /// A step is running. The host shows the step's presentation if one is
    /// active (`LifecycleStepUIBridge.presentation`), otherwise the splash.
    case running(LifecycleStep, LifecycleStepUIBridge)
    /// A step threw. The host shows an error UI offering retry.
    case failed(LifecycleFailure)
    /// All applicable steps finished — hand off to the app's main UI.
    case ready
}

/// Carries which step failed and why, so the failure UI can describe it and
/// the runner can retry from that step.
public struct LifecycleFailure {
    public let stepID: String
    public let error: any Error

    public init(stepID: String, error: any Error) {
        self.stepID = stepID
        self.error = error
    }
}

extension LifecyclePhase {
    public var isLaunching: Bool {
        if case .launching = self { true } else { false }
    }

    public var isReady: Bool {
        if case .ready = self { true } else { false }
    }

    /// The id of the currently running step, if any.
    public var runningStepID: String? {
        if case let .running(step, _) = self { step.id } else { nil }
    }

    /// The bridge of the currently running step, if any.
    public var runningBridge: LifecycleStepUIBridge? {
        if case let .running(_, bridge) = self { bridge } else { nil }
    }

    /// The failure, if the launch failed.
    public var failure: LifecycleFailure? {
        if case let .failed(failure) = self { failure } else { nil }
    }
}
