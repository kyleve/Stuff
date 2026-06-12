/// The single observable value the host renders. The launcher publishes a
/// `LaunchPhase`; `LaunchContainer` maps each case to UI.
public enum LaunchPhase {
    /// Before any presenting step — show the splash.
    case launching
    /// A step is running. The host shows the step's presentation if one is
    /// active (`StepHandle.presentation`), otherwise the splash.
    case running(LaunchStep, StepHandle)
    /// A step threw. The host shows an error UI offering retry.
    case failed(LaunchFailure)
    /// All applicable steps finished — hand off to the app's main UI.
    case ready
}

/// Carries which step failed and why, so the failure UI can describe it and
/// the launcher can retry from that step.
public struct LaunchFailure {
    public let stepID: String
    public let error: any Error

    public init(stepID: String, error: any Error) {
        self.stepID = stepID
        self.error = error
    }
}

extension LaunchPhase {
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

    /// The handle of the currently running step, if any.
    public var runningHandle: StepHandle? {
        if case let .running(_, handle) = self { handle } else { nil }
    }

    /// The failure, if the launch failed.
    public var failure: LaunchFailure? {
        if case let .failed(failure) = self { failure } else { nil }
    }
}
