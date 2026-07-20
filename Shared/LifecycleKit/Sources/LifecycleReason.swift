/// Why the app is launching this time.
///
/// The reason gates which steps run: a headless background relaunch (for a
/// location event, push, or background task) must not run UI-bearing steps
/// like onboarding, and the host should build no view tree at all (iOS never
/// shows UI for a background launch).
public enum LifecycleReason: Sendable, Hashable {
    /// A normal cold launch with a window the user will see.
    case userForeground
    /// A headless relaunch with no window, to service a system event.
    case background(LifecycleBackgroundCause)
    /// Launched under the UIScene lifecycle, where `UIApplication.applicationState`
    /// can't distinguish a user-tap launch from a headless wake at
    /// `didFinishLaunching` time — it reads `.background` for both. Behaves like
    /// a background launch (no window, background-safe steps only) until a scene
    /// activates and `LegacyLifecycleRunner.enterForeground()` promotes it to
    /// `.userForeground`. If no scene ever connects (a genuine headless wake),
    /// it honestly stays `.undetermined` for the process's life — the
    /// background-safe steps that ran serviced the wake, and no fabricated cause
    /// is ever claimed.
    case undetermined

    /// Whether the host should build no view tree for this launch — true for a
    /// headless `.background` relaunch and for an `.undetermined` one that has
    /// not yet been promoted (iOS shows no UI for either, and building the heavy
    /// content for a launch nobody sees defeats the headless path).
    public var buildsNoViewTree: Bool {
        switch self {
            case .userForeground: false
            case .background, .undetermined: true
        }
    }

    /// The single `LifecycleModeSet` bit a step's `modes` must contain for it
    /// to run under this reason. `.undetermined` gates to the background-safe
    /// subset: until a scene proves the launch is user-visible, only run the
    /// work a possible headless wake needs.
    public var modeSet: LifecycleModeSet {
        switch self {
            case .userForeground: .foreground
            case .background, .undetermined: .background
        }
    }
}

/// What woke the app into the background.
public enum LifecycleBackgroundCause: Sendable, Hashable {
    /// A CoreLocation event (significant-change, visit, region) relaunched us.
    case location
    /// A remote (push) notification delivered in the background.
    case remoteNotification
    /// A scheduled `BGTaskScheduler` task.
    case backgroundTask
    /// Any other system-initiated background launch.
    case other
}

/// The set of launch reasons a step applies to.
///
/// A step only runs when its `modes` contains the bit for the current
/// `LifecycleReason` (see `LifecycleReason.modeSet`).
public struct LifecycleModeSet: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Runs on a normal, user-visible foreground launch.
    public static let foreground = LifecycleModeSet(rawValue: 1 << 0)
    /// Runs on a headless background relaunch.
    public static let background = LifecycleModeSet(rawValue: 1 << 1)
    /// Runs regardless of why the app launched.
    public static let all: LifecycleModeSet = [.foreground, .background]
}
