/// LifecycleKit is a small, app-agnostic microframework for modeling app
/// startup (and its reverse, reset/teardown) as an ordered, conditional,
/// launch-reason-aware sequence of async steps.
///
/// The public surface lands incrementally: this namespace exists so the
/// module has a stable, documented anchor and a place to hang shared
/// metadata.
public enum LifecycleKit {
    /// Schema version of LifecycleKit's public model, bumped when the
    /// step/phase contract changes in a way consumers may care about.
    public static let version = 1
}
