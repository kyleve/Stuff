import Foundation

/// Widget gallery copy resolved from this extension's string catalog.
enum WidgetStrings {
    static var todayGalleryName: String {
        String(localized: "widget.gallery.today.name", defaultValue: "Today", bundle: .module)
    }

    static var todayGalleryDescription: String {
        String(
            localized: "widget.gallery.today.description",
            defaultValue: "Which region today counts for.",
            bundle: .module,
        )
    }

    static var yearTotalsGalleryName: String {
        String(
            localized: "widget.gallery.yearTotals.name",
            defaultValue: "Day Counts",
            bundle: .module,
        )
    }

    static var yearTotalsGalleryDescription: String {
        String(
            localized: "widget.gallery.yearTotals.description",
            defaultValue: "Days spent in each region this year.",
            bundle: .module,
        )
    }
}
