import RegionKit

/// Named browsing history. Its day values retain the original report attribution
/// so opening a correction never writes inferred catalog regions into history.
public struct ElsewhereReport: Hashable, Sendable {
    public let year: Int
    public let regions: [ElsewhereRegion]

    public init(year: Int, regions: [ElsewhereRegion]) {
        self.year = year
        self.regions = regions
    }
}
