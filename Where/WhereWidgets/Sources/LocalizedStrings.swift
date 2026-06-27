import LocalizationKit

/// Catalog-backed strings for the WhereWidgets extension.
///
/// Gallery name/description strings shown in the WidgetKit picker. Runtime
/// widget content is localized in WhereUI. Swift is the source of truth for
/// keys and English defaults; the sibling `Resources/Localizable.xcstrings` owns
/// translations. The root `./localize` script reconciles the catalog from this
/// file.
enum LocalizedStrings {
    enum Gallery {
        static let todayName: LocalizedString = .module("widget.gallery.today.name", "Today")

        static let todayDescription: LocalizedString = .module(
            "widget.gallery.today.description",
            "Which region today counts for.",
        )

        static let yearTotalsName: LocalizedString = .module(
            "widget.gallery.yearTotals.name",
            "Day Counts",
        )

        static let yearTotalsDescription: LocalizedString = .module(
            "widget.gallery.yearTotals.description",
            "Days spent in each region this year.",
        )
    }
}
