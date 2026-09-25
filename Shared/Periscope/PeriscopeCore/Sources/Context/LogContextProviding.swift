import Foundation
import ObjectiveC
import os

/// Gives a class a derived `.log` without passing loggers around.
///
/// The logger's scope is derived from the type and the instance: a root
/// scope named after the conforming type, with one child scope per instance
/// (`#1`, `#2`, …, cached by the system so an instance keeps its identity
/// for its lifetime). Filtering the type's scope subtree finds every
/// instance's events.
///
/// ```swift
/// final class PhotoController: LogContextProviding {
///     typealias LoggingScope = PhotoLogs   // omit for freeform-only logging
///
///     func refresh() {
///         log.info("refreshing")           // scoped to this instance
///         log { PhotoLogs.refreshed }
///     }
/// }
/// ```
///
/// Conformers log into ``Periscope/shared`` unless they override
/// ``logSystem``.
public protocol LogContextProviding: AnyObject {
    /// The scope that `log` uses. Defaults to ``FreeformLogScope`` for
    /// freeform-only conformers.
    associatedtype LoggingScope: LogScopeDefinition = FreeformLogScope

    /// The system this object logs into; defaults to ``Periscope/shared``.
    var logSystem: Periscope { get }
}

extension LogContextProviding {
    public var logSystem: Periscope {
        .shared
    }

    /// A logger scoped to this instance (type root scope → instance scope).
    public var log: Log<LoggingScope> {
        logSystem.instanceLog(for: self)
    }
}

extension Periscope {
    /// The instance-scoped logger backing ``LogContextProviding/log``.
    /// Repeated calls for the same instance return the same scope.
    public func instanceLog<Object: LogContextProviding>(
        for object: Object,
    ) -> Log<Object.LoggingScope> {
        let scopes = instanceScopes.scopes(for: object)
        defineScope(scopes.type)
        return Log(scopes: [scopes.instance], tags: [], recorder: self)
    }
}

/// The per-type and per-instance scopes `InstanceScopeRegistry` hands out.
struct InstanceScopePair {
    var type: LogScope
    var instance: LogScope
}

/// Caches one scope per live instance so `LogContextProviding.log` is stable
/// and readable: instances number `#1`, `#2`, … within their type's root
/// scope.
///
/// Entries are keyed by ``InstanceID`` (pointer *and* type) and evicted when
/// the instance deallocates — a retained tracker hangs off each instance via
/// the ObjC runtime, and its `deinit` (which runs strictly before the
/// allocator can recycle the address) removes the entry. Instance numbers
/// are monotonic and never reused within a run, so a persisted `#3` always
/// means one specific instance.
final class InstanceScopeRegistry: Sendable {
    private struct State {
        var scopesByInstance: [InstanceID: InstanceScopePair] = [:]
        var nextIndexByType: [String: Int] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Entries currently cached (i.e. tracked instances still alive).
    var trackedInstanceCount: Int {
        state.withLock { $0.scopesByInstance.count }
    }

    func scopes(for object: AnyObject) -> InstanceScopePair {
        let id = InstanceID(of: object)
        let (pair, isNew) = state.withLock { state -> (InstanceScopePair, Bool) in
            if let cached = state.scopesByInstance[id] {
                return (cached, false)
            }
            let index = state.nextIndexByType[id.typeName, default: 1]
            state.nextIndexByType[id.typeName] = index + 1
            let typeScope = LogScope.root(named: id.typeName)
            let pair = InstanceScopePair(
                type: typeScope,
                instance: typeScope.child(named: "#\(index)"),
            )
            state.scopesByInstance[id] = pair
            return (pair, true)
        }
        if isNew {
            installDeallocationTracker(on: object, id: id)
        }
        return pair
    }

    /// Called by a tracker's `deinit` when its host instance deallocates.
    func release(_ id: InstanceID) {
        state.withLock { $0.scopesByInstance[id] = nil }
    }

    /// Retain a tracker on the instance whose `deinit` evicts the cache
    /// entry. The association key is this registry's own pointer, so an
    /// object logged into two systems carries one tracker per registry.
    private func installDeallocationTracker(on object: AnyObject, id: InstanceID) {
        objc_setAssociatedObject(
            object,
            Unmanaged.passUnretained(self).toOpaque(),
            InstanceDeallocationTracker(id: id, registry: self),
            .OBJC_ASSOCIATION_RETAIN,
        )
    }
}

/// Released exactly when its host instance deallocates; evicts the host's
/// registry entry from `deinit`. Holds the registry weakly so trackers on
/// long-lived objects don't keep short-lived (test) registries alive.
private final class InstanceDeallocationTracker {
    private let id: InstanceID
    private weak var registry: InstanceScopeRegistry?

    init(id: InstanceID, registry: InstanceScopeRegistry) {
        self.id = id
        self.registry = registry
    }

    deinit {
        registry?.release(id)
    }
}
