import SnapshotKit
import SwiftUI

/// Annual-report configuration sheet. Its model is created afresh by
/// `YearView`, so opt-in GPS disclosure and identity fields never persist
/// between presentations.
struct YearExportView: View {
    @Bindable var model: YearExportModel
    let isDemo: Bool

    @State private var path: [YearPDFFile] = []
    @State private var generationTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                reportSection
                    .disabled(model.isGenerating)
                paperSection
                    .disabled(model.isGenerating)
                rawGPSSection
                    .disabled(model.isGenerating)
                generationSection
            }
            .navigationTitle(String(localized: .exportReportTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.isGenerating {
                        Button(String(localized: .commonCancel)) {
                            generationTask?.cancel()
                        }
                    } else {
                        Button(String(localized: .commonDone)) {
                            dismiss()
                        }
                    }
                }
            }
            .navigationDestination(for: YearPDFFile.self) { file in
                YearPDFPreviewView(file: file)
            }
            .alert(
                String(localized: .exportReportFailureTitle),
                isPresented: $model.isShowingFailure,
            ) {
                Button(String(localized: .commonOk), role: .cancel) {}
            } message: {
                Text(String(localized: .exportReportFailureMessage))
            }
        }
        .interactiveDismissDisabled(model.isGenerating)
    }

    private var reportSection: some View {
        Section {
            Picker(String(localized: .exportReportYear), selection: $model.selectedYear) {
                ForEach(model.availableYears, id: \.self) { year in
                    Text(WhereFormat.yearText(year)).tag(year)
                }
            }
            TextField(
                String(localized: .exportReportPreparedFor),
                text: $model.preparedFor,
            )
            .textContentType(.name)
            TextField(
                String(localized: .exportReportReference),
                text: $model.reference,
            )
        } header: {
            Text(String(localized: .exportReportDetailsHeader))
        } footer: {
            if isDemo {
                Label(
                    String(localized: .exportReportDemoFooter),
                    systemImage: "exclamationmark.triangle.fill",
                )
            }
        }
    }

    private var paperSection: some View {
        Section(String(localized: .exportReportPaperHeader)) {
            Picker(String(localized: .exportReportPaper), selection: $model.pageSize) {
                Text(String(localized: .exportReportPaperLetter)).tag(YearPDFPageSize.letter)
                Text(String(localized: .exportReportPaperA4)).tag(YearPDFPageSize.a4)
            }
            .pickerStyle(.segmented)
        }
    }

    private var rawGPSSection: some View {
        Section {
            Toggle(isOn: $model.includeRawGPS) {
                Label(
                    String(localized: .exportReportRawGpsToggle),
                    systemImage: "location.fill",
                )
            }
        } footer: {
            Text(String(localized: .exportReportRawGpsWarning))
        }
    }

    private var generationSection: some View {
        Section {
            Button {
                startGeneration()
            } label: {
                if model.isGenerating {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            String(localized: .exportReportGenerating),
                            systemImage: "doc.text.magnifyingglass",
                        )
                        if let progress = model.progressFraction {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                        }
                    }
                } else {
                    Label(
                        String(localized: .exportReportGenerate),
                        systemImage: "doc.richtext",
                    )
                }
            }
            .disabled(model.isGenerating)
        } footer: {
            Text(String(localized: .exportReportShareFooter))
        }
    }

    private func startGeneration() {
        generationTask?.cancel()
        generationTask = Task {
            if let file = await model.generate(isDemo: isDemo), !Task.isCancelled {
                path.append(file)
            }
        }
    }
}

#if DEBUG
    extension YearExportView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .screenDefaults) {
                let report = PreviewSupport.loadedYearReportModel()
                YearExportView(
                    model: YearExportModel(
                        reader: report.services.reports,
                        displayedYear: report.selectedYear,
                        calendar: report.calendar,
                        locale: Locale(identifier: "en_US"),
                        buildInfo: .current(bundle: .main),
                        now: report.now,
                    ),
                    isDemo: false,
                )
            }
            whereSnapshot(name: "Raw GPS warning", configurations: .phoneLightDark) {
                let report = PreviewSupport.loadedYearReportModel()
                let model = YearExportModel(
                    reader: report.services.reports,
                    displayedYear: report.selectedYear,
                    calendar: report.calendar,
                    locale: Locale(identifier: "en_US"),
                    buildInfo: .current(bundle: .main),
                    now: report.now,
                )
                model.includeRawGPS = true
                return YearExportView(model: model, isDemo: true)
            }
        }
    }

    #Preview {
        YearExportView.snapshotPreviews
    }
#endif
