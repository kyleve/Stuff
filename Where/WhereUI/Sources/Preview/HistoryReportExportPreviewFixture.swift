#if DEBUG
    import Foundation
    import Observation
    import SwiftUI
    import WhereCore

    /// Exercises the production export model with synthetic history. Saved simulates the
    /// system completion for an empty, complete year; it does not claim a physical file save.
    @MainActor
    @Observable
    final class HistoryReportExportPreviewFixture {
        enum Scenario: String, CaseIterable {
            case idle = "Ready"
            case incomplete = "NeedsReview"
            case saved = "Saved"
            case failure = "Failure"
        }

        struct State {
            let report: YearReportModel
            let export: HistoryReportExportModel
            let session: WhereSession
            let backup: BackupModel
            let app: WhereModel
        }

        let scenario: Scenario
        private let history = RecordingReportPreviewFixture(scenario: .mixed)
        private(set) var state: State?

        init(scenario: Scenario) {
            self.scenario = scenario
        }

        func prepare() async {
            guard state == nil else { return }
            await history.prepare()
            guard let report = history.report else {
                preconditionFailure("Export preview requires prepared history")
            }
            let year = scenario == .saved ? 2027 : 2026
            let source: any HistoryReportExporting = scenario == .failure
                ? FailedSource() : report.services.reports
            let model = HistoryReportExportModel(
                source: source,
                validate: report.services.validateDataAccess,
                year: year,
                isAvailable: true,
            )
            switch scenario {
                case .idle: break
                case .incomplete, .failure, .saved:
                    model.requestExport()
                    guard let requestID = model.requestID else {
                        preconditionFailure("Export preview must start an attempt")
                    }
                    await model.prepare(requestID)
                    if scenario == .saved {
                        guard let export = model.state.export else {
                            preconditionFailure("The unaffected preview year must be exportable")
                        }
                        model.complete(
                            .success(URL(fileURLWithPath: "/tmp/Where History 2027.csv")),
                            requestID: export.id,
                        )
                    }
            }
            state = State(
                report: report,
                export: model,
                session: WhereSession(
                    services: report.services,
                    preferences: report.preferences,
                    now: report.now,
                ),
                backup: BackupModel(services: report.services),
                app: PreviewSupport.loadedModel(),
            )
        }

        private struct FailedSource: HistoryReportExporting {
            func exportableYearCSV(for _: Int) async throws -> HistoryReportCSV {
                throw CocoaError(.fileReadUnknown)
            }
        }
    }

    struct HistoryReportExportPreview<Content: View>: View {
        let fixture: HistoryReportExportPreviewFixture
        @ViewBuilder let content: (HistoryReportExportPreviewFixture.State) -> Content

        var body: some View {
            if let state = fixture.state {
                content(state)
                    .environment(state.session)
                    .environment(state.app)
            } else {
                ProgressView()
            }
        }
    }

    #Preview { HistoryReportExportView.snapshotPreviews }
#endif
