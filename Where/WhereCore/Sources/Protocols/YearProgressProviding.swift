public protocol YearProgressProviding: Sendable {
    func availableYears() async -> [Int]
    func snapshot(for year: Int) async -> YearProgressSnapshot
}
