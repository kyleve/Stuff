public protocol YearDataProviding: Sendable {
    func availableYears() async -> [Int]
    func bundle(for year: Int) async -> YearDataBundle
}
