import SnapshotKit
import SwiftUI
import UniformTypeIdentifiers
import WhereCore

/// Exports one explicitly named report year. Review and export remain separate user intents.
struct HistoryReportExportView: View {
    let report: YearReportModel
    @State private var model: HistoryReportExportModel

    init(report: YearReportModel) {
        self.init(report: report, model: HistoryReportExportModel(
            source: report.services.reports,
            validate: report.services.validateDataAccess,
            year: report.selectedYear,
            isAvailable: report.services.recordingControlEdits.supportsRecordingControls,
        ))
    }

    init(report: YearReportModel, model: HistoryReportExportModel) {
        self.report = report
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        let requestID = model.requestID
        let exportID = model.state.export?.id
        Form {
            Section {
                LabeledContent(String(localized: .settingsYearLabel)) {
                    Text(model.year.formatted(.number.grouping(.never)))
                }
            } footer: { Text(String(localized: .historyExportDetail)) }
            switch model.state {
                case .idle, .ready: EmptyView()
                case .preparing:
                    Section { ProgressView(String(localized: .historyExportPreparing)) }
                case let .needsReview(completeness):
                    Section {
                        HistoryCompletenessNotice(completeness: completeness) {
                            model.showingReview = true
                        }
                    } footer: { Text(String(localized: .historyExportReviewDetail)) }
                case .saved:
                    Section {
                        Text(String(localized: .historyExportSaved))
                            .accessibilityIdentifier("where_history_export_saved")
                    }
                case .failed:
                    Section {
                        Text(String(localized: .historyExportFailed))
                            .accessibilityIdentifier("where_history_export_failed")
                    }
            }
            Section {
                Button(String(localized: .historyExportAction)) { model.requestExport() }
                    .disabled(!model.canExport)
                    .accessibilityIdentifier("where_history_export_prepare")
            }
        }
        .navigationTitle(String(localized: .historyExportTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: requestID) {
            if let requestID { await model.prepare(requestID) }
        }
        .onDisappear { model.cancelPreparation() }
        .sheet(isPresented: $model.showingReview) { ResolutionView(report: report) }
        .fileExporter(
            isPresented: $model.isPresentingExporter,
            item: model.state.export?.document,
            contentTypes: [.commaSeparatedText],
            defaultFilename: String(localized: .historyExportFilename(
                model.year.formatted(.number.grouping(.never)),
            )),
            onCompletion: { result in
                if let exportID { model.complete(result, requestID: exportID) }
            },
            onCancellation: {
                if let exportID { model.cancelExport(exportID) }
            },
        )
    }
}

#if DEBUG
    extension HistoryReportExportView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in HistoryReportExportPreviewFixture.Scenario.allCases {
                let fixture = HistoryReportExportPreviewFixture(scenario: scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .idle ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: fixture.prepare,
                ) {
                    HistoryReportExportPreview(fixture: fixture) { state in
                        NavigationStack {
                            HistoryReportExportView(report: state.report, model: state.export)
                        }
                    }
                }
            }
        }
    }

    #Preview { HistoryReportExportView.snapshotPreviews }
    extension HistoryReportExportView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            HistoryReportExportView.self,
            title: "Export history report",
            navigationContainer: .none,
            routes: [.modal(to: ResolutionView.flyoverID)],
        )
    }
#endif
