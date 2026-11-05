import RegionKit

/// One lazily loaded full-catalog lookup for an admitted service scope. History selection and
/// Elsewhere share it; live current-location attribution remains a separate tracked-region view.
public actor HistoryRegionAttribution {
    private static let logger = WhereLog.reporting(HistoryRegionAttributionLog.self)
    private var catalog: (any RegionAttributing)?

    public init() {}

    @_spi(Testing)
    public init(catalog: any RegionAttributing) {
        self.catalog = catalog
    }

    public func snapshot() -> any RegionAttributing {
        if let catalog { return catalog }
        let loaded = Self.logger.measure(.loadCatalog, budget: .seconds(1)) {
            RegionAttributor(for: RegionCatalog.shared.all)
        }
        catalog = loaded
        return loaded
    }
}
