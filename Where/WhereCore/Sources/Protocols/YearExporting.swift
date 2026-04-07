public protocol YearExporting: Sendable {
    func exportBundle(for year: Int) async -> YearExportBundle
}
