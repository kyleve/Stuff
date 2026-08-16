import Foundation
import PeriscopeCore
import UIKit
import WhereCore

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
/// `assetName` is the asset-catalog appiconset name. Whether it is primary or
/// alternate depends on the host's injected primary icon for this build.
/// `previewImageName` names an imageset in `AppIconPreviews.xcassets` — a
/// parallel catalog, since SwiftUI `Image` can't load appiconset images.
struct AppIconOption: Identifiable, Hashable, Codable {
    let id: AppIconID
    let displayName: String
    let assetName: String
    let previewImageName: String

    /// The value to pass to UIKit for a build with `primaryAppIconName`.
    func alternateIconName(primaryAppIconName: String) -> String? {
        assetName == primaryAppIconName ? nil : assetName
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

    /// The bundled manifest, degrading to an empty list when it can't be read.
    ///
    /// A missing or malformed `AppIcons.json` is a packaging error rather than
    /// anything a user can cause or recover from, so it trips an
    /// `assertionFailure` in debug and — in release — leaves the picker empty and
    /// the icon surfaces on their Classic fallback. Every best-effort caller goes
    /// through here, so the load failure can't be dropped at one site and
    /// reported at another.
    static func loadedOptions() -> [AppIconOption] {
        do {
            return try load(from: .module)
        } catch {
            logger(attachments: [.error(error, name: "load-error")]) {
                .manifestUnreadable(description: String(describing: error))
            }
            assertionFailure("Failed to load the bundled AppIcons.json manifest: \(error)")
            return []
        }
    }

    private static let logger = WhereLog.root(AppIconCatalogLog.self)

    /// Resolve which option matches the live `alternateIconName`, falling back to
    /// the primary (or first) option when the active icon isn't listed — e.g. it
    /// was removed from the manifest since it was last set, or `nil` (the primary
    /// icon, which carries no alternate name). The single source of truth for
    /// "which icon is selected", shared by the picker model and the launch splash.
    static func selectedOption(
        in options: [AppIconOption],
        current alternateIconName: String?,
        primaryAppIconName: String,
    ) -> AppIconOption? {
        options.first {
            $0.alternateIconName(primaryAppIconName: primaryAppIconName) == alternateIconName
        }
            ?? options.first { $0.assetName == primaryAppIconName }
            ?? options.first
    }

    /// The preview-catalog image name of the currently selected icon, resolved
    /// from the live `UIApplication.shared.alternateIconName` against the
    /// manifest and falling back to the bundled "Classic" art. Shared by every
    /// in-app surface that renders the selected icon (launch splash and shared
    /// loading states) so they stay in lockstep.
    @MainActor static func liveSelectedPreviewImageName(
        primaryAppIconName: String,
    ) -> String {
        let options = loadedOptions()
        let selected = selectedOption(
            in: options,
            current: UIApplication.shared.alternateIconName,
            primaryAppIconName: primaryAppIconName,
        )
        return selected?.previewImageName ?? "AppIconClassic"
    }

    private struct Manifest: Codable {
        let icons: [AppIconOption]
    }
}
