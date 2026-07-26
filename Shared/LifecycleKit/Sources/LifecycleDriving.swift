/// The type-erased drive surface `LifecycleKitUI`'s environment proxy talks
/// to: everything a nested view may do to a runner without knowing its
/// `Launch` type (an environment value must be non-generic).
///
/// The erasure stays inside the package: `LifecycleProxy` erases a typed
/// `LaunchPlan` + input at the call site (where the compiler has checked
/// them) and forwards through this seam.
@MainActor
package protocol LifecycleDriving: AnyObject, Sendable {
    /// See `LifecycleRunner.enterForeground()`.
    func enterForeground() async

    /// `LifecycleRunner.teardown(_:input:)` with the plan pre-erased by the
    /// typed caller.
    func teardownErased(nodes: [LaunchPlanNode], input: any Sendable) async
}

extension LifecycleRunner: LifecycleDriving {}
