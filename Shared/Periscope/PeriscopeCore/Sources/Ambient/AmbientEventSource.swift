import Foundation

/// A source of ambient/environmental events. Built-ins cover app lifecycle,
/// memory warnings, network path, thermal state, and low power mode;
/// apps conform to add their own (push registration, sync status, …).
///
/// Sources are registered with ``Periscope/startAmbientSource(_:)``, which
/// retains them for the process lifetime and hands them a logger under the
/// shared ambient scope.
public protocol AmbientEventSource: Sendable {
    /// Begin observing and log every observed change into `log`. Called
    /// exactly once, when the source is registered — sources observe for
    /// the process lifetime and are not required to tolerate repeated
    /// starts (the notification-based built-ins would double their
    /// observers).
    func start(log: Log<AmbientEvent>)
}

extension Periscope {
    /// Retain `source` and start it with a logger under this system's
    /// ambient scope.
    public func startAmbientSource(_ source: some AmbientEventSource) {
        retainAmbientSource(source)
        source.start(log: Log<AmbientEvent>(recorder: self))
    }

    /// Start every built-in ambient source: network path, thermal state,
    /// low power mode, and (where UIKit exists) app lifecycle and memory
    /// warnings.
    public func startDefaultAmbientSources() {
        startAmbientSource(NetworkPathAmbientSource())
        startAmbientSource(ThermalStateAmbientSource())
        startAmbientSource(LowPowerModeAmbientSource())
        #if canImport(UIKit)
            startAmbientSource(AppLifecycleAmbientSource())
            startAmbientSource(MemoryWarningAmbientSource())
        #endif
    }
}
