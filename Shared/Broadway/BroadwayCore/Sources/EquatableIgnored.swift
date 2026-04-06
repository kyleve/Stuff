//
//  EquatableIgnored.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/31/26.
//

import Foundation

/// A property wrapper that ignores the wrapped value when comparing for equality.
///
/// Use `@EquatableIgnored` to mark properties that should not affect the result of `==` when the enclosing type conforms to `Equatable`.
///
/// The equality operator (`==`) for this wrapper always returns `true`, regardless of the underlying value.
///
/// ```swift
/// struct Example: Equatable {
///     var id: Int
///     @EquatableIgnored var cache: Any?
/// }
/// ```
/// In this example, `cache` will never affect the equality of two `Example` instances.
@propertyWrapper public struct EquatableIgnored<Value>: Equatable, Hashable, @unchecked Sendable {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public static func == (_: Self, _: Self) -> Bool {
        true
    }

    public func hash(into _: inout Hasher) {}
}
