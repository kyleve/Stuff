@testable import LifecycleKit

/// A configurable gate for engine tests: identity, mode gating, and a
/// phantom `Value`, so each test declares exactly the gate it needs without
/// minting a one-off conforming type. (Steps need no fixture in the function
/// style — they're closures at the call site.)
struct FixtureGate<Value: Sendable>: LifecycleGate {
    let id: AnyHashable
    var modes: LifecycleModeSet = .foreground

    init(_ id: AnyHashable, modes: LifecycleModeSet = .foreground) {
        self.id = id
        self.modes = modes
    }
}
