//
//  BStylesheets.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/3/26.
//

import Foundation

/// A keyed cache of ``BStylesheet`` instances, scoped to a specific
/// combination of traits and themes. Stylesheets are created lazily on
/// first access and cached for subsequent lookups with the same key.
public struct BStylesheets: Equatable, @unchecked Sendable {
    /// The current trait values (accessibility, size class, etc.).
    public var traits: BTraits {
        get { config.traits }
        set { config.traits = newValue }
    }

    /// The current theme values.
    public var themes: BThemes {
        get { config.themes }
        set { config.themes = newValue }
    }

    /// The inputs that determine stylesheet identity. Two `BStylesheets`
    /// values are equal when their configurations match, regardless of
    /// how much of the cache has been lazily populated.
    var config: Config

    struct Config: Equatable {
        var traits: BTraits
        var themes: BThemes
    }

    // MARK: Equatable

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.config == rhs.config
    }

    // MARK: Lookup

    /// Returns the cached stylesheet of the given type, creating it lazily if needed.
    ///
    /// - Throws: ``StylesheetError/cyclicDependency(path:)`` if creation triggers
    ///   a dependency cycle, or ``StylesheetError/creationFailed(type:underlying:)``
    ///   if the stylesheet's initializer throws.
    public func get<Stylesheet: BStylesheet>(_: Stylesheet.Type) throws(StylesheetError) -> Stylesheet {
        let key = Key(stylesheet: .init(Stylesheet.self), traits: traits, themes: themes)

        guard let value = cache[key], let value = value.base as? Stylesheet else {
            let id = TypeIdentifier(Stylesheet.self)

            let creating = _creating._unsafeUnderlyingValue

            if let cycleStart = creating.firstIndex(of: id) {
                let path = creating[cycleStart...].map(\.debugDescription) + [id.debugDescription]
                throw .cyclicDependency(path: path)
            }

            _creating._unsafeUnderlyingValue.append(id)
            defer { _creating._unsafeUnderlyingValue.removeLast() }

            let context = SlicingContext(themes: themes, stylesheets: self)

            do {
                let new = try Stylesheet(context: context)
                _cache._unsafeUnderlyingValue[key] = AnyEquatable(new)
                return new
            } catch let error as StylesheetError {
                throw error
            } catch {
                throw .creationFailed(type: id.debugDescription, underlying: error)
            }
        }

        return value
    }

    /// Explicitly sets a cached stylesheet value for the given type,
    /// replacing any previously cached instance for the current traits and themes.
    mutating func set<Stylesheet: BStylesheet>(_ newValue: Stylesheet) {
        let key = Key(stylesheet: .init(Stylesheet.self), traits: traits, themes: themes)
        cache[key] = AnyEquatable(newValue)
    }

    // MARK: Cache

    // TODO: Eventually we should clear this out on memory warnings for sheets not accessed within 10(?) min
    @CopyOnWrite private var cache: [Key: AnyEquatable] = [:]

    @CopyOnWrite private var creating: [TypeIdentifier] = []

    /// Cache key combining the stylesheet type with the traits and themes
    /// that were active at creation time.
    struct Key: Hashable {
        let stylesheet: TypeIdentifier
        let traits: BTraits
        let themes: BThemes
    }
}
