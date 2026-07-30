#if DEBUG
    import Observation

    /// Per-frame state for toggling the Locations Resolve toolbar affordance.
    @MainActor
    @Observable
    final class WhereFlyoverLocationsState {
        let report: YearReportModel
        var showsResolve = true {
            didSet {
                guard oldValue != showsResolve else {
                    return
                }
                apply()
            }
        }

        init(report: YearReportModel) {
            self.report = report
            apply()
        }

        func reset() {
            showsResolve = true
            apply()
        }

        private func apply() {
            report.setDataIssueCount(showsResolve ? 4 : 0)
        }
    }
#endif
