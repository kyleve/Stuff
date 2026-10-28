/// The navigation boundary Flyover provides around one registered screen.
public enum FlyoverNavigationContainer: Hashable, Sendable {
    /// Isolate the screen in its own stack so navigation preferences stay inside its frame.
    case stack
    /// Add no container because the content owns its navigation root or is not a screen.
    case none
}
