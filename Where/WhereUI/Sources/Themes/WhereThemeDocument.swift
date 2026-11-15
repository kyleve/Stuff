import Foundation
import ViewDocumentCore
import WhereCore

/// A complete root or a sparse child. Catalog resolution produces a complete, validated theme.
public struct WhereThemeDocument: Codable, Hashable, Sendable {
    public struct ID: RawRepresentable, Codable, Hashable, Sendable {
        public static let standard = Self(rawValue: "standard")
        public static let flat = Self(rawValue: "flat")
        public static let halloween = Self(rawValue: "halloween")
        public static let holiday = Self(rawValue: "holiday")
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
    public var parent: ID?
    public var values: WhereThemeValues
    public var components: WhereThemeComponents

    // Version 1 source compatibility. New documents use parent and component surfaces.
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
        parent = .init(rawValue: fallback == .standard ? "standard" : "flat")
        values = .init(colors: nil, fonts: nil, surfaces: nil)
        components = .init()
        self.schemaVersion = schemaVersion
        self.id = id
        self.fallback = fallback
        self.appearance = appearance
        self.layers = layers
    }

    public init(
        id: ID,
        parent: ID?,
        values: WhereThemeValues,
        appearance: WhereThemeAppearance,
        components: WhereThemeComponents,
    ) {
        schemaVersion = 2
        self.id = id
        self.parent = parent
        self.values = values
        self.appearance = appearance
        self.components = components
        fallback = parent == .flat || id == .flat ? .flat : .standard
        layers = .init()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, parent, values, appearance, components, fallback, layers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 || schemaVersion == 2 else {
            throw WhereThemeValidationError(
                path: "schemaVersion",
                reason: "Unsupported theme schema version",
            )
        }
        id = try container.decode(ID.self, forKey: .id)
        appearance = try container
            .decodeIfPresent(WhereThemeAppearance.self, forKey: .appearance) ?? .init()
        values = try container.decodeIfPresent(WhereThemeValues.self, forKey: .values) ?? .init(
            colors: nil,
            fonts: nil,
            surfaces: nil,
        )
        components = try container
            .decodeIfPresent(WhereThemeComponents.self, forKey: .components) ?? .init()
        layers = try container.decodeIfPresent(Layers.self, forKey: .layers) ?? .init()
        fallback = try container.decodeIfPresent(Fallback.self, forKey: .fallback) ?? .standard
        parent = schemaVersion == 1 ? .init(rawValue: fallback == .standard ? "standard" : "flat") :
            try container.decodeIfPresent(
                ID.self,
                forKey: .parent,
            )
        if schemaVersion == 1 { self = try converted() }
        else { fallback = parent == .flat || id == .flat ? .flat : .standard }
    }

    public func encode(to encoder: any Encoder) throws {
        let document = try converted()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(2, forKey: .schemaVersion)
        try container.encode(document.id, forKey: .id)
        try container.encodeIfPresent(document.parent, forKey: .parent)
        try container.encode(document.values, forKey: .values)
        try container.encode(document.appearance, forKey: .appearance)
        try container.encode(document.components, forKey: .components)
    }

    /// Imports retain native content and translate the old finite decoration slots once.
    func converted() throws -> Self {
        guard schemaVersion == 1 else { return self }
        var result = self
        result.schemaVersion = 2
        result.appearance = try WhereThemeLegacyConversion.appearance(
            appearance,
            fallback: fallback,
        )
        for slot in Slot.allCases {
            let documents = layers[slot]
            guard documents.count <= 8,
                  Set(documents.map(\.root.id)).count == documents.count
            else {
                throw WhereThemeValidationError(
                    path: "layers.\(slot.rawValue)",
                    reason: "Too many layers or duplicate layer identity",
                )
            }
        }
        for role in WhereThemeComponents.Role.allCases {
            let slots: [Slot] = switch role {
                case .locations: [.locationsBackground]
                case .regularCard: [.regularCardBackground, .regularCardOverlay]
                case .compactCard: [.compactCardBackground, .compactCardOverlay]
                case .elsewhere, .year, .settings, .sheet, .elsewhereCard, .summary, .forecastPanel,
                     .calendarMonth, .timelineEntry, .section, .welcome, .privacy: []
            }
            let art = slots.flatMap { slot in
                layers[slot].enumerated().map { index, document in
                    WhereThemeArtwork(
                        id: .init(rawValue: "\(slot.rawValue)-\(index)"),
                        document: document,
                        placement: .init(
                            anchor: .center,
                            size: .relative(
                                width: 1,
                                height: 1,
                                maximumWidth: 2048,
                                maximumHeight: 2048,
                            ),
                            offset: .init(x: 0, y: 0),
                            plane: .interior,
                            outsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
                        ),
                        role: .ornament,
                        opacity: .constant(1),
                    )
                }
            }
            if !art.isEmpty {
                var component = result.components[role] ?? .init()
                component.artwork = art
                result.components[role] = component
            }
        }
        // A legacy literal remains the owner of its value after conversion.
        if appearance.card?.regular?
            .surface !=
            nil
        {
            result.components.regularCard = result.components.regularCard ?? .init(); result
                .components.regularCard?.surface = .clear
        }
        if appearance.card?.compact?
            .surface !=
            nil
        {
            result.components.compactCard = result.components.compactCard ?? .init(); result
                .components.compactCard?.surface = .clear
        }
        if appearance.locationsBackground?
            .paper !=
            nil
        {
            result.components.locations = result.components.locations ?? .init(); result.components
                .locations?.background = .clear
        }
        result.layers = .init()
        return result
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
