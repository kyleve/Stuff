//
//  BStylesheet.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/31/26.
//

import Foundation

/// A type that computes derived style values from a ``SlicingContext``.
///
/// Conform to this protocol to define a stylesheet that is lazily created
/// and cached by ``BStylesheets``. A stylesheet's `init` receives the current
/// traits and themes and may access other stylesheets through the context;
/// circular dependencies are detected at runtime and throw a
/// ``CyclicDependencyError``.
public protocol BStylesheet: Equatable {
    init(context: SlicingContext) throws
}

/// The context passed to ``BStylesheet/init(context:)`` during lazy creation,
/// providing access to the current traits, themes, and other stylesheets. The
/// cache is keyed on traits and themes, so a stylesheet that reads them is
/// re-created whenever they change.
public struct SlicingContext {
    public var traits: BTraits
    public var themes: BThemes
    public var stylesheets: BStylesheets
}
