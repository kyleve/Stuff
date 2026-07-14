import Foundation
import os

/// A source of ambient/environmental events. Built-ins cover app lifecycle,
/// memory warnings, network path, thermal state, and low power mode;
/// apps conform to add their own (push registration, sync status, …).
///
/// Sources are registered with ``Periscope/startAmbientSource(_:)``, which
/// retains them and hands them a logger under the shared ambient scope;
/// ``Periscope/stopAmbientSources()`` stops and releases them.
public protocol AmbientEventSource: Sendable {
    /// Begin observing and log every observed change into `log`. A
    /// restart must replace the prior observation, not double it (the
    /// built-ins swap their observer tokens wholesale).
    func start(log: Log<AmbientEvent>)

    /// End the observation: remove notification observers, cancel
    /// monitors. Nothing may keep logging (or retaining the logger's
    /// system) after this returns.
    func stop()
}

/// Retains `NotificationCenter` observer tokens for a `Sendable` source
/// struct. The block-based observer API holds its token strongly *in the
/// center* until removal — dropping the token doesn't end the observation,
/// it makes it unremovable (and immortalizes everything the block
/// captures, including the logger's whole system). Public because
/// app-defined notification-based sources face the same trap.
public struct AmbientObserverTokens: Sendable {
    private let tokens = OSAllocatedUnfairLock<[any NSObjectProtocol]>(uncheckedState: [])

    public init() {}

    /// Store `new`, removing any previously stored observers first — a
    /// restart replaces the observation rather than doubling it.
    public func replace(with new: [any NSObjectProtocol]) {
        let old = tokens.withLockUnchecked { boxed -> [any NSObjectProtocol] in
            let old = boxed
            boxed = new
            return old
        }
        for token in old {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func removeAll() {
        replace(with: [])
    }
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
