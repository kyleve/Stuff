import Foundation

/// Presentation-ready data for Where's store-free glance surfaces.
///
/// The app builds this from its authoritative report and publishes it inside
/// `widget-snapshot.json`. Consumers render the supplied names and ordering;
/// they never open the user's store or repeat region aggregation.
public struct WhereSurfaceSnapshot: Codable, Hashable, Sendable {
    /// A display-ready region shared by today's presence and year-to-date rows.
    public struct Region: Codable, Hashable, Identifiable, Sendable {
        /// The region's stable data identifier.
        public let id: String
        /// The localized name resolved by the publishing app.
        public let name: String
        /// A user-selected emoji, when the region has one.
        public let emoji: String?
        /// A user-selected SF Symbol name, when the region has one.
        public let symbolName: String?

        public init(id: String, name: String, emoji: String?, symbolName: String?) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.symbolName = symbolName
        }
    }

    /// One ranked year-to-date region total.
    public struct DayCount: Codable, Hashable, Identifiable, Sendable {
        public var id: String {
            region.id
        }

        public let region: Region
        public let days: Int

        public init(region: Region, days: Int) {
            self.region = region
            self.days = days
        }
    }

    /// The logical day represented by `todayRegions`.
    public let day: Date
    /// Regions observed on `day`, already in canonical display order.
    public let todayRegions: [Region]
    /// The Gregorian calendar year represented by `yearToDate`.
    public let year: Int
    /// The top year-to-date day counts, already ranked for display.
    public let yearToDate: [DayCount]

    public init(
        day: Date,
        todayRegions: [Region],
        year: Int,
        yearToDate: [DayCount],
    ) {
        self.day = day
        self.todayRegions = todayRegions
        self.year = year
        self.yearToDate = yearToDate
    }
}
