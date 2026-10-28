//
//  TypeIdentifier.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/29/26.
//

import Foundation

/// A wrapper around `ObjectIdentifier` that retains the original metatype
/// for debug output. Equality and hashing are based solely on the
/// `ObjectIdentifier`, so two `TypeIdentifier` values match iff they
/// refer to the same type.
struct TypeIdentifier: Equatable, Hashable, CustomDebugStringConvertible {
    let identifier: ObjectIdentifier
    let type: Any.Type

    init(_ type: (some Any).Type) {
        identifier = .init(type)
        self.type = type
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    var debugDescription: String {
        "\(type)"
    }
}
