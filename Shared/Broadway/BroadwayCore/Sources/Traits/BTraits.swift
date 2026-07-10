//
//  BTraits.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/3/26.
//

import Foundation
import UIKit

// MARK: - BTraits

/// A type-keyed container of ``BTraitsValue`` conforming values
/// representing the current environment (accessibility, size classes, etc.).
///
/// Create a traits container with ``system`` for the built-in set of
/// observed traits, or call ``register(_:)`` to add custom types.
/// Accessing a type that hasn't been explicitly set returns
/// its ``BTraitsValue/defaultValue``.
public struct BTraits: Equatable, Hashable, @unchecked Sendable {
    init() {}

    /// A traits container pre-registered with all built-in system trait types.
    @MainActor public static var system: BTraits {
        var traits = BTraits()

        traits.register(BAccessibility.self)
        traits.register(BMode.self)
        traits.register(BContentSizeCategory.self)

        return traits
    }

    // MARK: Subscript

    /// Gets or sets the trait for the given type. Returns
    /// ``BTraitsValue/defaultValue`` if no value has been set.
    public subscript<Value: BTraitsValue>(_: Value.Type) -> Value {
        get {
            let id = TypeIdentifier(Value.self)

            guard let value = storage[id], let value = value.base as? Value else {
                return Value.defaultValue
            }

            return value
        }

        set {
            let id = TypeIdentifier(Value.self)

            storage[id] = AnyHashable(newValue)
        }
    }

    // MARK: Applying Overrides

    public mutating func merge(with overrides: Overrides) {
        for (id, value) in overrides.values {
            storage[id] = value
        }
    }

    public func merging(with overrides: Overrides) -> BTraits {
        var copy = self
        copy.merge(with: overrides)
        return copy
    }

    // MARK: Registration

    /// Registers a ``BTraitsValue`` type so that ``readCurrentValues(from:)``
    /// and ``BTraitsObserver`` know about it.
    @MainActor public mutating func register<V: BTraitsValue>(_: V.Type) {
        registrations.append(Registration(
            id: TypeIdentifier(V.self),
            readCurrentValue: { vc in AnyHashable(V.currentValue(from: vc)) },
            createObserver: { vc, onChange in
                V.makeObserver(with: vc) { newValue in onChange(AnyHashable(newValue)) }
            },
        ))
    }

    /// Reads the live value for every registered trait type from the
    /// given view controller hierarchy and stores it.
    @MainActor public mutating func readCurrentValues(
        from viewController: UIViewController,
    ) {
        for reg in registrations {
            storage[reg.id] = reg.readCurrentValue(viewController)
        }
    }

    // MARK: Internal

    mutating func setValue(_ value: AnyHashable, for id: TypeIdentifier) {
        storage[id] = value
    }

    struct Registration: @unchecked Sendable {
        let id: TypeIdentifier
        let readCurrentValue: @MainActor @Sendable (UIViewController) -> AnyHashable
        let createObserver: @MainActor @Sendable (
            UIViewController,
            @escaping @MainActor @Sendable (AnyHashable) -> Void
        ) -> any BTraitsValueObserver
    }

    // MARK: Private

    @CopyOnWrite private var storage: [TypeIdentifier: AnyHashable] = [:]
    @EquatableIgnored private(set) var registrations: [Registration] = []
}

// MARK: - BTraitsValue

/// A hashable value that can be stored in ``BTraits``.
///
/// Conforming types provide a ``defaultValue`` that is returned when
/// the trait has not been explicitly set. Types that need live system
/// observation override ``currentValue(from:)`` and
/// ``makeObserver(onChange:)`` to supply a snapshot and an observer.
public protocol BTraitsValue: Hashable {
    associatedtype Observer: BTraitsValueObserver

    static var defaultValue: Self { get }

    /// Returns the current live value by reading from the view controller
    /// hierarchy. Defaults to ``defaultValue``.
    @MainActor static func currentValue(from viewController: UIViewController) -> Self

    @MainActor static func makeObserver(
        with viewController: UIViewController,
        onChange: @MainActor @escaping @Sendable (Self) -> Void,
    ) -> Observer
}

extension BTraitsValue {
    @MainActor public static func currentValue(
        from _: UIViewController,
    ) -> Self {
        defaultValue
    }
}

// MARK: - BTraitsValueObserver

/// The interface for an observer that monitors changes to
/// a single ``BTraitsValue`` type. Retained by ``BTraitsObserver``.
@MainActor public protocol BTraitsValueObserver: AnyObject {
    func start()
    func stop()
}

/// A no-op observer type conformers can return from ``BTraitsValue/makeObserver``
/// when a trait has no live system source to subscribe to.
@MainActor public final class NeverObserver: BTraitsValueObserver {
    public init() {}
    public func start() {}
    public func stop() {}
}
