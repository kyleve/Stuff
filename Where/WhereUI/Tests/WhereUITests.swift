import SwiftUI
import Testing
import WhereCore
import WhereTesting
import WhereUI

@Test
@MainActor
func rootViewBuilds() throws {
    let vc = UIHostingController(
        rootView: RootView(
            viewModel: RootViewModel(provider: StubYearProgressProvider()),
        ),
    )

    try show(vc) { hosted in
        #expect(hosted.view != nil)
    }
}

private struct StubYearProgressProvider: YearProgressProviding {
    func availableYears() async -> [Int] {
        [2026]
    }

    func snapshot(for year: Int) async -> YearProgressSnapshot {
        YearProgressSnapshot(
            year: year,
            primarySummaries: [
                .init(jurisdiction: .california, totalDays: 10),
                .init(jurisdiction: .newYork, totalDays: 8),
            ],
            secondarySummaries: [
                .init(jurisdiction: .unknown, totalDays: 1),
            ],
            trackingStatus: .needsReview,
            recentDays: [
                .init(
                    dateLabel: "Apr 6",
                    jurisdictions: [.california, .newYork],
                    note: "Multiple jurisdictions logged",
                ),
            ],
        )
    }
}
