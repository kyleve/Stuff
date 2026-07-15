//
//  BTraits+Overrides.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/31/26.
//

import Foundation

extension BTraits {
    /// Allows overriding traits with specific values.
    public struct Overrides: Equatable, Hashable, @unchecked Sendable {
        public init() {}

        // MARK: Subscript

        /// Gets or sets the trait for the given type. Returns `nil`  if no value has been set.
        public subscript<Value: BTraitsValue>(_: Value.Type) -> Value? {
            get {
                let id = TypeIdentifier(Value.self)

                guard let value = storage[id], let value = value.base as? Value else {
                    return nil
                }

                return value
            }

            set {
                let id = TypeIdentifier(Value.self)

                if let newValue {
                    storage[id] = AnyHashable(newValue)
                } else {
                    storage[id] = nil
                }
            }
        }

        @CopyOnWrite private var storage: [TypeIdentifier: AnyHashable] = [:]

        var values: [TypeIdentifier: AnyHashable] {
            storage
        }
    }
}
