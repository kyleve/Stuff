#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    struct WhereFlyoverLocationsStateTests {
        @Test func togglesAndResetsResolveToolbarCount() {
            let report = PreviewSupport.loadedYearReportModel()
            let state = WhereFlyoverLocationsState(report: report)

            #expect(report.dataIssueCount == 4)

            state.showsResolve = false
            #expect(report.dataIssueCount == 0)

            state.reset()
            #expect(state.showsResolve)
            #expect(report.dataIssueCount == 4)
        }
    }
#endif
