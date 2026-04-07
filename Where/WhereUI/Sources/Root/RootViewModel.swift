import Foundation
import Observation
import WhereCore

@MainActor
@Observable
public final class RootViewModel {
    public private(set) var selectedYear: Int
    public private(set) var availableYears: [Int] = []
    public private(set) var snapshot: YearProgressSnapshot?
    public private(set) var isLoading = false

    private let provider: any YearProgressProviding

    public init(
        provider: any YearProgressProviding,
        selectedYear: Int? = nil,
    ) {
        self.provider = provider
        self.selectedYear = selectedYear ?? Calendar.current.component(.year, from: Date())
    }

    public func load() async {
        isLoading = true
        let years = await provider.availableYears()
        let fallbackYear = Calendar.current.component(.year, from: Date())
        availableYears = years.isEmpty ? [fallbackYear] : years

        if !availableYears.contains(selectedYear) {
            selectedYear = availableYears.last ?? fallbackYear
        }

        snapshot = await provider.snapshot(for: selectedYear)
        isLoading = false
    }

    public func selectYear(_ year: Int) async {
        selectedYear = year
        snapshot = await provider.snapshot(for: year)
    }
}
