//
//  AnyEquatable.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/3/26.
//

import Foundation

/// A type-erased wrapper around any `Equatable` value.
///
/// `AnyEquatable` stores an `Equatable` value and its comparison closure,
/// allowing heterogeneous equality checks at runtime. Two `AnyEquatable`
/// instances are equal only when they wrap the same type and that type's
/// `==` operator returns `true`.
///
/// ```swift
/// let a = AnyEquatable(42)
/// let b = AnyEquatable(42)
/// let c = AnyEquatable("hello")
///
/// a == b  // true  — same type, same value
/// a == c  // false — different types
/// ```
struct AnyEquatable: Equatable, @unchecked Sendable {
    /// The type-erased value.
    let base: Any

    private let compare: (AnyEquatable) -> Bool

    /// Creates a type-erased equatable wrapper around the given value.
    init<Value: Equatable>(_ typedValue: Value) {
        base = typedValue

        compare = { other in
            guard let rhs = other.base as? Value else {
                return false
            }

            return typedValue == rhs
        }
    }

    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool {
        lhs.compare(rhs)
    }
}
