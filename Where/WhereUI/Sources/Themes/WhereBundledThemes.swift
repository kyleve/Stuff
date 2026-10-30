import Foundation
import PeriscopeCore
import ViewDocumentCore
import ViewDocumentUI
import WhereCore

/// Bundled definitions share the same catalog and preparation boundary as imported documents.
@MainActor
enum WhereBundledThemes {
    static var documents: Result<[WhereThemeDocument], any Error> {
        WhereBundledThemeDefinitions.documents
    }

    private static let standard = Result { try catalog().prepare(
        .init(rawValue: "standard"),
        assets: .init(images: [:], symbols: [:]),
    ) }
    private static let flat = Result { try catalog().prepare(
        .init(rawValue: "flat"),
        assets: .init(images: [:], symbols: [:]),
    ) }
    private static let halloween = Result { try catalog().prepare(
        .halloween,
        assets: assets(.halloween),
    ) }
    private static let holiday = Result { try catalog().prepare(
        .holiday,
        assets: assets(.holiday),
    ) }

    /// The host approves bundle resources; documents never choose filesystem paths.
    static func assets(_ theme: WhereTheme) throws -> ViewDocumentAssets {
        let illustrations: [ViewAssetID: String] = switch theme {
            case .standard, .alternate: [:]
            case .halloween: [
                    .init(rawValue: "halloween.pumpkins"): "HalloweenPumpkins",
                    .init(rawValue: "halloween.moon"): "HalloweenMoon",
                    .init(rawValue: "halloween.vine"): "HalloweenVine",
                ]
            case .holiday: [
                    .init(rawValue: "holiday.bells"): "HolidayBells",
                    .init(rawValue: "holiday.bough"): "HolidayBough",
                    .init(rawValue: "holiday.woodland"): "HolidayWoodland",
                ]
        }
        return try WhereBundledThemeAssets.load(illustrations: illustrations)
    }

    static func load(_ name: String) throws -> WhereThemeDocument {
        try WhereBundledThemeDefinitions
            .load(name)
    }

    static func catalog() throws -> WhereThemeCatalog {
        try .init(documents: documents.get())
    }

    static func preparedOrFallback(_ theme: WhereTheme) -> PreparedWhereThemeDocument? {
        do { return try prepared(theme) }
        catch { WhereBundledThemeDefinitions.reportPackagingFailure(error); return nil }
    }

    static func prepared(_ theme: WhereTheme) throws -> PreparedWhereThemeDocument {
        switch theme {
            case .standard: try standard.get()
            case .alternate: try flat.get()
            case .halloween: try halloween.get()
            case .holiday: try holiday.get()
        }
    }
}

/// Thread-safe immutable definitions also supply off-tree stylesheet fallbacks.
enum WhereBundledThemeDefinitions {
    static let documents: Result<[WhereThemeDocument], any Error> = Result {
        try ["StandardTheme", "FlatTheme", "HalloweenTheme", "HolidayTheme"].map { try load($0) }
    }

    private static let standard = Result {
        try WhereThemeCatalog(documents: documents.get()).resolve(.init(rawValue: "standard"))
    }

    private static let flat = Result {
        try WhereThemeCatalog(documents: documents.get()).resolve(.init(rawValue: "flat"))
    }

    private static let halloween = Result {
        try WhereThemeCatalog(documents: documents.get()).resolve(.halloween)
    }

    private static let holiday = Result {
        try WhereThemeCatalog(documents: documents.get()).resolve(.holiday)
    }

    static func resolved(_ theme: WhereTheme) throws -> ResolvedWhereTheme {
        switch theme {
            case .standard: try standard.get()
            case .alternate: try flat.get()
            case .halloween: try halloween.get()
            case .holiday: try holiday.get()
        }
    }

    static func load(_ name: String) throws -> WhereThemeDocument {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw WhereThemeValidationError(path: name, reason: "Missing bundled theme")
        }
        return try JSONDecoder().decode(WhereThemeDocument.self, from: Data(contentsOf: url))
    }

    static func reportPackagingFailure(_ error: any Error) {
        WhereLog.root(WhereThemeLog.self).bundleUnreadable(error: .restricted(.errorDetails, error))
        assertionFailure("Invalid bundled theme: \(error)")
    }
}
