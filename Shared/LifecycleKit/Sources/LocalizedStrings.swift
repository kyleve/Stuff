import LocalizationKit

/// Catalog-backed strings for LifecycleKit.
///
/// Swift is the source of truth for keys and English defaults; the sibling
/// `Resources/Localizable.xcstrings` owns translations. The root `./localize`
/// script reconciles the catalog from this file.
enum LocalizedStrings {
    enum Failure {
        static let launchTitle: LocalizedString = .module(
            "failure.launch.title",
            "Couldn't finish launching",
        )

        static let launchRetry: LocalizedString = .module(
            "failure.launch.retry",
            "Try Again",
        )
    }
}
