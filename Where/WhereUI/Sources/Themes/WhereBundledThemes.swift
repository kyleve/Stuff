import Foundation
import PeriscopeCore
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
        }
    }
}

/// Thread-safe immutable definitions also supply off-tree stylesheet fallbacks.
enum WhereBundledThemeDefinitions {
    static let documents: Result<[WhereThemeDocument], any Error> = Result {
        try ["StandardTheme", "FlatTheme"].map { try load($0) }
    }

    private static let standard = Result {
        try WhereThemeCatalog(documents: documents.get()).resolve(.init(rawValue: "standard"))
    }

    private static let flat = Result {
        try WhereThemeCatalog(documents: documents.get()).resolve(.init(rawValue: "flat"))
    }

    static func resolved(_ theme: WhereTheme) throws -> ResolvedWhereTheme {
        switch theme { case .standard: try standard.get(); case .alternate: try flat.get() }
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
