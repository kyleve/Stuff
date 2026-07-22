/// The type-erased drive surface `LifecycleKitUI`'s environment proxy talks
/// to: everything a nested view may do to a runner without knowing its
/// `Launch` type (an environment value must be non-generic).
///
/// The erasure stays inside the package: `LifecycleProxy` captures the typed
/// teardown input + body at the call site (where the compiler has checked
/// them) into a plain closure and forwards through this seam.
@MainActor
package protocol LifecycleDriving: AnyObject, Sendable {
    /// See `LifecycleRunner.enterForeground()`.
    func enterForeground() async

    /// `LifecycleRunner.teardown(input:_:)` with the input captured by the
    /// typed caller.
    func teardownErased(_ run: @escaping @MainActor (LifecycleContext) async throws -> Void) async
}

extension LifecycleRunner: LifecycleDriving {}
