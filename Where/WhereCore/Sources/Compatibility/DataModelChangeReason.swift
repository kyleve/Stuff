import Foundation

/// Display copy for a version, published so builds older than the change can explain it.
public struct DataModelChangeReason: Codable, Equatable, Sendable {
    private let translations: [String: String]

    public init(translations: [String: String]) {
        self.translations = translations
    }

    init(resource: LocalizedStringResource, bundle: Bundle) {
        translations = bundle.localizations.reduce(into: [:]) { translations, language in
            guard language != "Base" else { return }
            let translation = bundle.localizedString(
                forKey: resource.key,
                value: nil,
                table: resource.table,
                localizations: [Locale.Language(identifier: language)],
            )
            if translation != resource.key, !translation.isEmpty {
                translations[language] = translation
            }
        }
    }

    public func localized(preferredLocales: [Locale]) -> String? {
        let available = translations.filter { !$0.value.isEmpty }.keys.sorted()
        guard !available.isEmpty else { return nil }
        let preferred = Bundle.preferredLocalizations(
            from: available,
            forPreferences: preferredLocales.map { $0.identifier(.bcp47) } + ["en"],
        ).first
        return preferred.flatMap { translations[$0] }
    }
}
