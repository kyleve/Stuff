import Foundation
import ViewDocumentCore
import WhereCore

/// A versioned, sparse theme. Fallbacks are built-ins, so inheritance cannot form a cycle.
public struct WhereThemeDocument: Codable, Hashable, Sendable {
    public struct ID: RawRepresentable, Codable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public enum Fallback: String, Codable, Hashable, Sendable {
        case standard, flat
        var theme: WhereTheme {
            switch self { case .standard: .standard; case .flat: .alternate }
        }
    }

    public var schemaVersion: Int
    public var id: ID
    public var fallback: Fallback
    public var appearance: WhereThemeAppearance
    public var layers: Layers

    public init(
        schemaVersion: Int,
        id: ID,
        fallback: Fallback,
        appearance: WhereThemeAppearance,
        layers: Layers,
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.fallback = fallback
        self.appearance = appearance
        self.layers = layers
    }

    public enum Slot: String, CaseIterable, Codable, Hashable, Sendable {
        case locationsBackground, regularCardBackground, regularCardOverlay, compactCardBackground,
             compactCardOverlay
    }

    public struct Layers: Codable, Hashable, Sendable {
        public var locationsBackground: [ViewDocument]?
        public var regularCardBackground: [ViewDocument]?
        public var regularCardOverlay: [ViewDocument]?
        public var compactCardBackground: [ViewDocument]?
        public var compactCardOverlay: [ViewDocument]?
        public init() {}
        public subscript(slot: Slot) -> [ViewDocument] {
            switch slot {
                case .locationsBackground: locationsBackground ?? []
                case .regularCardBackground: regularCardBackground ?? []
                case .regularCardOverlay: regularCardOverlay ?? []
                case .compactCardBackground: compactCardBackground ?? []
                case .compactCardOverlay: compactCardOverlay ?? []
            }
        }
    }
}
