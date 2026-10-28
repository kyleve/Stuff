//
//  BThemes.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/29/26.
//

import Foundation

/// A named, hashable theme value stored in ``BThemes``.
///
/// Conform to this protocol for app-level theme types (e.g. color palettes,
/// typography scales) that are used by stylesheets during slicing.
/// Provide a ``defaultValue`` that is returned when the theme has not been
/// explicitly set.
public protocol BTheme: Equatable, Hashable {
    static var defaultValue: Self { get }
}

/// A type-keyed container of ``BTheme`` values.
///
/// Themes are always present; accessing a type that hasn't been explicitly
/// set returns its ``BTheme/defaultValue``.
public struct BThemes: Equatable, Hashable, @unchecked Sendable {
    public init() {}

    /// Gets or sets the theme for the given type. Returns
    /// ``BTheme/defaultValue`` if no value has been explicitly set.
    public subscript<Theme: BTheme>(_: Theme.Type) -> Theme {
        get {
            let id = TypeIdentifier(Theme.self)

            guard let value = themes[id], let value = value.base as? Theme else {
                return Theme.defaultValue
            }

            return value
        }

        set {
            let id = TypeIdentifier(Theme.self)
            themes[id] = AnyHashable(newValue)
        }
    }

    @CopyOnWrite private var themes: [TypeIdentifier: AnyHashable] = [:]
}
