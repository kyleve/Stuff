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
/// and cached by ``BStylesheets``. A stylesheet's `init` receives the
/// current themes and may access other stylesheets through the context;
/// circular dependencies are detected at runtime and throw a
/// ``CyclicDependencyError``.
public protocol BStylesheet: Equatable {
    init(context: SlicingContext) throws
}

/// The context passed to ``BStylesheet/init(context:)`` during lazy creation,
/// providing access to the current themes and other stylesheets.
public struct SlicingContext {
    public var themes: BThemes
    public var stylesheets: BStylesheets
}
