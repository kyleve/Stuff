import CoreMotion
import Observation

/// Publishes the device's tilt as a normalized `roll`/`pitch` pair so the
/// card's light sheen can react to how the phone is held, like a coated card
/// shifting beneath a light source.
///
/// Backed by `CMMotionManager`'s device-motion gravity vector, whose `x`/`y`
/// components already land in roughly `-1...1`. Device motion needs no
/// `Info.plist` usage string and no authorization (unlike motion *activity*),
/// so this is safe to start without prompting. On hardware that can't provide
/// motion (Simulator, the unit-test host, Mac), `start()` is a no-op and the
/// values stay at zero with `hasLiveSample == false`, so a consumer can render
/// its deterministic static pose instead.
///
/// `@MainActor` so the observable state is mutated on the main actor (where
/// SwiftUI reads it); CoreMotion delivers updates on the `.main` queue, so the
/// handler hops in via `MainActor.assumeIsolated` rather than spinning up a
/// `Task` per frame.
@MainActor
@Observable
public final class TiltProvider {
    /// Left/right tilt, roughly `-1...1`. Zero when flat or unavailable.
    public private(set) var roll: Double = 0
    /// Forward/back tilt, roughly `-1...1`. Zero when flat or unavailable.
    public private(set) var pitch: Double = 0
    /// Whether device motion has delivered a value since the latest `start()`.
    /// Internal because only WhereUI's tilt-finish renderers need to distinguish
    /// a real flat-device zero from the pre-sample/unavailable state.
    private(set) var hasLiveSample = false

    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private var isRunning = false

    public init() {}

    /// A neutral, never-started instance for previews and tests so views that
    /// want a `TiltProvider` don't have to touch CoreMotion.
    public static let preview = TiltProvider()

    /// Begin device-motion updates if the hardware supports them. Idempotent;
    /// a no-op when motion is unavailable or already running.
    public func start() {
        guard !isRunning, motionManager.isDeviceMotionAvailable else { return }
        isRunning = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let x = motion.gravity.x
            let y = motion.gravity.y
            // Delivered on the `.main` queue, so we're already on the main
            // actor; assume it to update observable state without a hop.
            MainActor.assumeIsolated {
                self.roll = x
                self.pitch = y
                self.hasLiveSample = true
            }
        }
    }

    /// Pause updates and relax back to neutral. Idempotent. Callers drive this
    /// from the view lifecycle; if it's ever missed, releasing the provider
    /// also releases (and stops) its `CMMotionManager`, and the `[weak self]`
    /// handler no-ops in the meantime.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        roll = 0
        pitch = 0
        hasLiveSample = false
    }
}
