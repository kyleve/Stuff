import Foundation
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
///     typealias LogEventType = PhotoLogs   // omit for freeform-only logging
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
    /// The structured event type `log` emits. Defaults to ``Message`` for
    /// freeform-only conformers.
    associatedtype LogEventType: LogEvent = Message

    /// The system this object logs into; defaults to ``Periscope/shared``.
    var logSystem: Periscope { get }
}

extension LogContextProviding {
    public var logSystem: Periscope {
        .shared
    }

    /// A logger scoped to this instance (type root scope → instance scope).
    public var log: Log<LogEventType> {
        logSystem.instanceLog(for: self)
    }
}

extension Periscope {
    /// The instance-scoped logger backing ``LogContextProviding/log``.
    /// Repeated calls for the same instance return the same scope.
    public func instanceLog<Object: LogContextProviding>(
        for object: Object,
    ) -> Log<Object.LogEventType> {
        let scopes = instanceScopes.scopes(for: object)
        defineScope(scopes.type)
        return Log(scopes: [scopes.instance], tags: [:], recorder: self)
    }
}

/// The per-type and per-instance scopes `InstanceScopeRegistry` hands out.
struct InstanceScopePair {
    var type: LogScope
    var instance: LogScope
}

/// Caches one scope per live instance so `LogContextProviding.log` is stable
/// and readable: instances number `#1`, `#2`, … within their type's root
/// scope. Entries are one small struct per logging instance and live for the
/// process — intended for controllers and model objects, not per-request
/// throwaways.
final class InstanceScopeRegistry: Sendable {
    private struct State {
        var scopesByInstance: [ObjectIdentifier: InstanceScopePair] = [:]
        var nextIndexByType: [String: Int] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func scopes(for object: AnyObject) -> InstanceScopePair {
        let id = ObjectIdentifier(object)
        let typeName = String(describing: type(of: object))
        return state.withLock { state in
            if let cached = state.scopesByInstance[id] {
                return cached
            }
            let index = state.nextIndexByType[typeName, default: 1]
            state.nextIndexByType[typeName] = index + 1
            let typeScope = LogScope.root(named: typeName)
            let pair = InstanceScopePair(
                type: typeScope,
                instance: typeScope.child(named: "#\(index)"),
            )
            state.scopesByInstance[id] = pair
            return pair
        }
    }
}
