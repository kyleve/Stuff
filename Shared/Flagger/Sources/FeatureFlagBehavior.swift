/// A type-level policy controlling when a flag's effective value may change.
public protocol FeatureFlagBehavior: Sendable {
    static var kind: FeatureFlagBehaviorKind { get }
}

/// Resolves when its Flagger opens and stays fixed for that instance's lifetime.
public enum ReadOnceOnLaunch: FeatureFlagBehavior {
    public static let kind = FeatureFlagBehaviorKind.readOnceOnLaunch
}

/// Resolves on its first read and stays fixed for that Flagger instance's lifetime.
public enum ReadOnceOnFirstAccess: FeatureFlagBehavior {
    public static let kind = FeatureFlagBehaviorKind.readOnceOnFirstAccess
}

/// Resolves from the current override and may be updated while Flagger is alive.
public enum LiveUpdating: FeatureFlagBehavior {
    public static let kind = FeatureFlagBehaviorKind.liveUpdating
}

public enum FeatureFlagBehaviorKind: String, Codable, Sendable {
    case readOnceOnLaunch
    case readOnceOnFirstAccess
    case liveUpdating
}
