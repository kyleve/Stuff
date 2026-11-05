import RegionKit

/// Named browsing history. Its day values retain the original report attribution
/// so opening a correction never writes inferred catalog regions into history.
public struct ElsewhereReport: Hashable, Sendable {
    public let year: Int
    public let regions: [ElsewhereRegion]
    public let completeness: HistoryCompleteness

    public init(year: Int, regions: [ElsewhereRegion]) {
        self.init(year: year, regions: regions, completeness: .foundation)
    }

    public init(year: Int, regions: [ElsewhereRegion], completeness: HistoryCompleteness) {
        self.year = year
        self.regions = regions
        self.completeness = completeness
    }
}
