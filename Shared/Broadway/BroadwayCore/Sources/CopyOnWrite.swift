//
//  CopyOnWrite.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/3/26.
//

import Foundation

/// A property wrapper that provides copy-on-write semantics for value types.
///
/// `CopyOnWrite` wraps a value in a reference-counted box, deferring copies
/// until mutation occurs. This is useful for large value types (e.g., structs
/// containing collections or other expensive-to-copy data) where copies are
/// frequent but mutations are rare.
///
/// When the wrapped value is mutated and the underlying storage is shared
/// (i.e., multiple `CopyOnWrite` instances reference the same box), a new
/// copy of the storage is created. If the storage is uniquely referenced,
/// the mutation happens in place without copying.
///
/// ### Usage as a Property Wrapper
///
/// ```swift
/// struct MyModel {
///     @CopyOnWrite var largeData: [Int]
/// }
/// ```
///
/// ### Usage as a Standalone Type
///
/// ```swift
/// var a = CopyOnWrite(wrappedValue: [1, 2, 3])
/// var b = a  // No copy yet — both share the same storage.
/// b.wrappedValue.append(4)  // Copy triggered — `a` is unaffected.
/// ```
@propertyWrapper
public struct CopyOnWrite<Value> {
    public init(wrappedValue: Value) {
        box = .init(value: wrappedValue)
    }

    /// The wrapped value, with copy-on-write mutation semantics.
    ///
    /// On read, returns the current value directly. On write, creates a new
    /// copy of the underlying storage if it is shared with other instances;
    /// otherwise mutates in place.
    public var wrappedValue: Value {
        get {
            _unsafeUnderlyingValue
        }

        set {
            if !isKnownUniquelyReferenced(&box) {
                box = .init(value: newValue)
            } else {
                box.value = newValue
            }
        }
    }

    /// Direct access to the underlying value **without** copy-on-write protection.
    ///
    /// - Important: Mutations through this property bypass the uniqueness check,
    ///   meaning changes will be visible to all instances that share the same
    ///   underlying storage. Only use this when you are certain the storage is
    ///   not shared, or when shared mutation is intentional.
    @_spi(CopyOnWrite) public var _unsafeUnderlyingValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    private var box: Box

    fileprivate class Box {
        var value: Value

        init(value: Value) {
            self.value = value
        }
    }
}

extension CopyOnWrite: Equatable where Value: Equatable {}
extension CopyOnWrite: Hashable where Value: Hashable {}
extension CopyOnWrite: @unchecked Sendable where Value: Sendable {}

extension CopyOnWrite.Box: Equatable where Value: Equatable {
    static func == (lhs: CopyOnWrite.Box, rhs: CopyOnWrite.Box) -> Bool {
        lhs === rhs || lhs.value == rhs.value
    }
}

extension CopyOnWrite.Box: Hashable where Value: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}
