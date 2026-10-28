//
//  StylesheetError.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/31/26.
//

import Foundation

/// Errors thrown by ``BStylesheets/get(_:)`` during stylesheet resolution.
public enum StylesheetError: Error, CustomStringConvertible {
    /// A stylesheet's initialization created a dependency cycle.
    ///
    /// The associated `path` describes the cycle, e.g. `["A", "B", "A"]`
    /// means `A` depends on `B` which depends on `A`.
    case cyclicDependency(path: [String])

    /// A stylesheet's `init(context:)` threw a non-stylesheet error.
    case creationFailed(type: String, underlying: any Error)

    public var description: String {
        switch self {
            case let .cyclicDependency(path):
                "Stylesheet dependency cycle: \(path.joined(separator: " → "))"
            case let .creationFailed(type, underlying):
                "Failed to create stylesheet '\(type)': \(underlying)"
        }
    }
}
