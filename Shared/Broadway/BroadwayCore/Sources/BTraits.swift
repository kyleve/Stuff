//
//  BTraits.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/3/26.
//

import Foundation

extension BTraits {
    public var accessibility: BAccessibility {
        get { self[BAccessibility.self] }
        set { self[BAccessibility.self] = newValue }
    }
}

extension BAccessibility: BTraitsValue {
    public static var defaultValue: Self {
        .init()
    }
}

/// A type-keyed container of ``BTraitsValue`` conforming values
/// representing the current environment (accessibility, size classes, etc.).
///
/// Traits are always present; accessing a type that hasn't been explicitly
/// set returns its ``BTraitsValue/defaultValue``.
public struct BTraits: Equatable, Hashable, @unchecked Sendable {
    public init() {}

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

    @CopyOnWrite private var storage: [TypeIdentifier: AnyHashable] = [:]
}

/// A hashable value that can be stored in ``BTraits``.
///
/// Conforming types provide a ``defaultValue`` that is returned when
/// the trait has not been explicitly set.
public protocol BTraitsValue: Hashable {
    static var defaultValue: Self { get }
}
