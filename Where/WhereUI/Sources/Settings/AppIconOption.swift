import Foundation

/// A typed, `Hashable` identifier for an app-icon option.
///
/// String-backed so the catalog can stay data-driven (the `./icons` script
/// edits `AppIcons.json`, never Swift), while call sites still pass a distinct
/// type instead of a bare `String` that could silently typo.
struct AppIconID: Hashable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension AppIconID: Codable {
    /// Encoded as a bare string ("classic") in the manifest, not a wrapped
    /// object, so the JSON stays hand-editable by the `./icons` script.
    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One selectable app icon, decoded from the bundled `AppIcons.json` manifest
/// that the `./icons` script maintains.
///
/// `alternateIconName` is the asset-catalog appiconset name passed to
/// `setAlternateIconName`; `nil` marks the primary icon. `previewImageName`
/// names an imageset in `AppIconPreviews.xcassets` — a parallel catalog, since
/// SwiftUI `Image` can't load appiconset images — rendered by the picker.
struct AppIconOption: Identifiable, Hashable, Codable {
    let id: AppIconID
    let displayName: String
    let alternateIconName: String?
    let previewImageName: String

    /// Whether this is the primary (default) icon, i.e. `setAlternateIconName(nil)`.
    var isPrimary: Bool {
        alternateIconName == nil
    }
}

/// Loads the bundled app-icon manifest. The list of selectable icons lives in
/// `AppIcons.json` (kept in sync with the asset catalogs by `./icons`) rather
/// than hard-coded here, so adding an icon never touches Swift.
enum AppIconCatalog {
    enum LoadError: Error {
        case manifestMissing
    }

    static func load(from bundle: Bundle = .module) throws -> [AppIconOption] {
        guard let url = bundle.url(forResource: "AppIcons", withExtension: "json") else {
            throw LoadError.manifestMissing
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data).icons
    }

    private struct Manifest: Codable {
        let icons: [AppIconOption]
    }
}
