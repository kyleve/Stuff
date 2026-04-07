import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import WhereCore

struct ManualEntryView: View {
    let rootViewModel: RootViewModel
    @State private var viewModel: ManualEntryViewModel
    @State private var draft = ManualEntryDraft(
        timestamp: Date(),
        jurisdiction: .california,
        kind: .supplemental,
    )
    @State private var isPresentingEditor = false
    @State private var importingEvidenceEntryID: UUID?
    @State private var isExportingPlainText = false
    @State private var isExportingPDF = false

    init(
        rootViewModel: RootViewModel,
        viewModel: ManualEntryViewModel,
    ) {
        self.rootViewModel = rootViewModel
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            List {
                Section("Selected Year") {
                    Text(String(rootViewModel.selectedYear))
                }

                Section("Export") {
                    ReportActionRow(
                        title: "Plain Text",
                        statusText: viewModel.reportStatusText(
                            for: rootViewModel.selectedYear,
                            format: .plainText,
                        ),
                        onExport: {
                            Task {
                                await viewModel.preparePlainTextExport(for: rootViewModel.selectedYear)
                                if viewModel.plainTextExportDocument != nil {
                                    isExportingPlainText = true
                                }
                            }
                        },
                        onShare: {
                            Task {
                                await viewModel.preparePlainTextShare(for: rootViewModel.selectedYear)
                            }
                        },
                    )

                    ReportActionRow(
                        title: "PDF",
                        statusText: viewModel.reportStatusText(
                            for: rootViewModel.selectedYear,
                            format: .pdf,
                        ),
                        onExport: {
                            Task {
                                await viewModel.preparePDFExport(for: rootViewModel.selectedYear)
                                if viewModel.pdfExportDocument != nil {
                                    isExportingPDF = true
                                }
                            }
                        },
                        onShare: {
                            Task {
                                await viewModel.preparePDFShare(for: rootViewModel.selectedYear)
                            }
                        },
                    )
                }

                if viewModel.isLoading, viewModel.daySections.isEmpty {
                    Section("Manual Entries") {
                        ProgressView("Loading manual entries...")
                    }
                } else if viewModel.daySections.isEmpty {
                    Section("Manual Entries") {
                        ContentUnavailableView(
                            "No Manual Entries",
                            systemImage: "square.and.pencil",
                            description: Text("Add a correction or supplemental note for \(rootViewModel.selectedYear)."),
                        )
                    }
                } else {
                    ForEach(viewModel.daySections) { daySection in
                        Section {
                            ForEach(daySection.entries) { dayEntry in
                                entryRow(for: dayEntry)
                            }
                        } header: {
                            dayHeader(for: daySection)
                        }
                    }
                }
            }
            .navigationTitle("Manual")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draft = ManualEntryDraft(
                            timestamp: Date(),
                            jurisdiction: .california,
                            kind: .supplemental,
                        )
                        isPresentingEditor = true
                    } label: {
                        Label("Add Entry", systemImage: "plus")
                    }
                }
            }
            .accessibilityIdentifier("where_manual")
        }
        .task(id: rootViewModel.selectedYear) {
            await viewModel.load(for: rootViewModel.selectedYear)
        }
        .sheet(isPresented: $isPresentingEditor) {
            ManualEntryEditorView(draft: draft) { draft in
                Task {
                    await viewModel.save(
                        draft,
                        year: rootViewModel.selectedYear,
                    )
                    await rootViewModel.selectYear(rootViewModel.selectedYear)
                }
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importingEvidenceEntryID != nil },
                set: { isPresented in
                    if !isPresented {
                        importingEvidenceEntryID = nil
                    }
                },
            ),
            allowedContentTypes: [.content, .data, .image, .pdf],
            allowsMultipleSelection: false,
        ) { result in
            guard
                case let .success(urls) = result,
                let fileURL = urls.first,
                let entryID = importingEvidenceEntryID
            else {
                importingEvidenceEntryID = nil
                return
            }

            Task {
                let didAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }

                await viewModel.importEvidence(
                    manualEntryID: entryID,
                    fileURL: fileURL,
                    year: rootViewModel.selectedYear,
                )
            }

            importingEvidenceEntryID = nil
        }
        .fileExporter(
            isPresented: $isExportingPlainText,
            document: viewModel.plainTextExportDocument,
            contentType: .plainText,
            defaultFilename: viewModel.plainTextFilename,
        ) { _ in
            viewModel.clearPlainTextExport()
        }
        .fileExporter(
            isPresented: $isExportingPDF,
            document: viewModel.pdfExportDocument,
            contentType: .pdf,
            defaultFilename: viewModel.pdfFilename,
        ) { _ in
            viewModel.clearPDFExport()
        }
        .alert(
            "Manual Entry Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearError()
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .quickLookPreview(
            Binding(
                get: { viewModel.previewURL },
                set: { url in
                    if url == nil {
                        viewModel.clearPreview()
                    }
                },
            ),
        )
        #if canImport(UIKit)
        .sheet(
            isPresented: Binding(
                get: { viewModel.shareURL != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearShare()
                    }
                },
            ),
        ) {
            if let shareURL = viewModel.shareURL {
                ActivityView(activityItems: [shareURL])
            }
        }
        #endif
    }

    private func dayHeader(for section: ManualEntryDaySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(section.date, format: .dateTime.weekday(.abbreviated).month().day().year())
                    .font(.headline)

                if section.changesTrackedOutcome {
                    Text("Outcome Changed")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }

            Text("Tracked: \(jurisdictionSummary(section.trackedJurisdictions, emptyLabel: "No tracked data"))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Final: \(jurisdictionSummary(section.finalJurisdictions, emptyLabel: "No final jurisdictions"))")
                .font(.caption)
                .foregroundStyle(section.changesTrackedOutcome ? Color.accentColor : .secondary)

            if let note = section.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }

    private func entryRow(for dayEntry: ManualEntryDayRecord) -> some View {
        let record = dayEntry.record

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.entry.timestamp, format: .dateTime.hour().minute())
                        .font(.headline)
                    Text(record.entry.jurisdiction.displayName)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text(record.entry.kind.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())

                    if dayEntry.changesDayOutcome {
                        Text("Changes Day")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
            }

            if let note = record.entry.note {
                Text(note)
            }

            if record.attachments.isEmpty {
                Text("No evidence attached")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Evidence (\(record.attachments.count))") {
                    ForEach(record.attachments) { attachment in
                        HStack(alignment: .top) {
                            EvidenceAttachmentPreviewView(
                                attachment: attachment,
                                stagedURL: viewModel.inlineEvidenceURL(for: attachment),
                            )
                            .task(id: attachment.id) {
                                await viewModel.loadInlineEvidenceIfNeeded(for: attachment)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                Button("Preview") {
                                    Task {
                                        await viewModel.prepareEvidencePreview(for: attachment)
                                    }
                                }

                                Button("Share") {
                                    Task {
                                        await viewModel.prepareEvidenceShare(for: attachment)
                                    }
                                }

                                Button("Delete", role: .destructive) {
                                    Task {
                                        await viewModel.deleteEvidence(
                                            attachment,
                                            year: rootViewModel.selectedYear,
                                        )
                                    }
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            HStack {
                Button("Edit") {
                    draft = ManualEntryDraft(entry: record.entry)
                    isPresentingEditor = true
                }

                Button("Add Evidence") {
                    importingEvidenceEntryID = record.id
                }

                Spacer()

                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteEntry(
                            id: record.id,
                            year: rootViewModel.selectedYear,
                        )
                        await rootViewModel.selectYear(rootViewModel.selectedYear)
                    }
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
    }

    private func jurisdictionSummary(
        _ jurisdictions: [TaxJurisdiction],
        emptyLabel: String,
    ) -> String {
        guard !jurisdictions.isEmpty else {
            return emptyLabel
        }

        return jurisdictions.map(\.displayName).joined(separator: ", ")
    }
}
