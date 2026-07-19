import Foundation

/// A source of ambient/environmental events. Built-ins cover app lifecycle,
/// memory warnings, network path, thermal state, low power mode, and
/// accessibility settings; apps conform to add their own (push
/// registration, sync status, …).
///
/// Sources are registered with ``Periscope/startAmbientSource(_:)``, which
/// retains them and hands them a logger under the shared ambient scope;
/// ``Periscope/stopAmbientSources()`` stops and releases them. `AnyObject`
/// because a source owns mutable observation state (monitors, any
/// last-value filter) across the `start`/`stop` pair — notification-based
/// sources get that for free from ``NotificationAmbientSource``.
public protocol AmbientEventSource: AnyObject, Sendable {
    /// Begin observing and log observed changes into `log` — a source may
    /// filter no-op updates against its own last state before emitting
    /// (so a signal that re-fires without changing doesn't flood the log).
    /// A restart must replace the prior observation, not double it.
    func start(log: Log<AmbientEvent>)

    /// End the observation: remove notification observers, cancel
    /// monitors. Nothing may keep logging (or retaining the logger's
    /// system) after this returns.
    func stop()
}

extension Periscope {
    /// Retain `source` and start it with a logger under this system's
    /// ambient scope.
    public func startAmbientSource(_ source: some AmbientEventSource) {
        retainAmbientSource(source)
        source.start(log: Log<AmbientEvent>(recorder: self))
    }

    /// Stop and release every ambient source started on this system — the
    /// counterpart to ``startAmbientSource(_:)``. Sources stop observing
    /// immediately; events they already emitted still deliver.
    public func stopAmbientSources() {
        for source in releaseAmbientSources() {
            source.stop()
        }
    }

    /// Start every built-in ambient source: network path, thermal state,
    /// low power mode, and (where UIKit exists) app lifecycle, memory
    /// warnings, and accessibility settings.
    public func startDefaultAmbientSources() {
        startAmbientSource(NetworkPathAmbientSource())
        startAmbientSource(ThermalStateAmbientSource())
        startAmbientSource(LowPowerModeAmbientSource())
        #if canImport(UIKit)
            startAmbientSource(AppLifecycleAmbientSource())
            startAmbientSource(MemoryWarningAmbientSource())
            startAmbientSource(AccessibilityAmbientSource())
        #endif
    }
}
