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
    @State private var isPresentingBackfill = false
    @State private var isImportingPackage = false
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

                Section("Data") {
                    Text("Locations and manual entries are stored on device. If you saw unfamiliar content before, it may have come from earlier seeded sample data or persisted local data from a previous run.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Reset Stored Data", role: .destructive) {
                        viewModel.requestResetConfirmation()
                    }
                }

                Section("Import") {
                    Text("Backfill prior travel with day-level entries, or import a package with a manifest and evidence files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Backfill Days") {
                        isPresentingBackfill = true
                    }

                    Button("Import Package") {
                        isImportingPackage = true
                    }
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
        .sheet(isPresented: $isPresentingBackfill) {
            ManualBackfillView(initialDate: Date()) { request in
                Task {
                    await viewModel.previewBackfill(request)
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
        .fileImporter(
            isPresented: $isImportingPackage,
            allowedContentTypes: allowedPackageTypes,
            allowsMultipleSelection: false,
        ) { result in
            guard
                case let .success(urls) = result,
                let directoryURL = urls.first
            else {
                return
            }

            Task {
                await viewModel.previewPackage(at: directoryURL)
            }
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
        .confirmationDialog(
            "Reset Stored Data?",
            isPresented: Binding(
                get: { viewModel.isShowingResetConfirmation },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissResetConfirmation()
                    }
                },
            ),
            titleVisibility: .visible,
        ) {
            Button("Reset All Data", role: .destructive) {
                Task {
                    await viewModel.resetAllData(for: rootViewModel.selectedYear)
                    await rootViewModel.reloadAfterDataReset()
                }
            }

            Button("Cancel", role: .cancel) {
                viewModel.dismissResetConfirmation()
            }
        } message: {
            Text("This removes all stored locations, manual entries, evidence metadata, and export activity from this device.")
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isShowingImportPreview },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissImportPreview()
                    }
                },
            ),
        ) {
            NavigationStack {
                List {
                    if let preview = viewModel.activeImportPreview {
                        Section("Summary") {
                            LabeledContent("Source", value: viewModel.importSourceDescription ?? "Import")
                            LabeledContent("Entries", value: String(preview.entryCount))
                            LabeledContent("Evidence Attachments", value: String(preview.evidenceAttachmentCount))

                            if let yearSpan = preview.yearSpan {
                                LabeledContent("Years", value: yearSpan.lowerBound == yearSpan.upperBound ? String(yearSpan.lowerBound) : "\(yearSpan.lowerBound)-\(yearSpan.upperBound)")
                            }

                            if preview.sharedEvidenceAttachmentCount > 0 {
                                LabeledContent("Shared Files", value: String(preview.sharedEvidenceAttachmentCount))
                            }
                        }

                        if !preview.issues.isEmpty {
                            Section("Validation") {
                                ForEach(preview.issues) { issue in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(issue.severity.rawValue.capitalized)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                                        Text(issue.message)
                                            .font(.footnote)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        if !preview.entries.isEmpty {
                            Section("Preview") {
                                ForEach(preview.entries.prefix(20)) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.timestamp, format: .dateTime.month().day().year().hour().minute())
                                            .font(.headline)
                                        Text(entry.jurisdiction.displayName)
                                            .foregroundStyle(.secondary)

                                        if !entry.note.isEmpty {
                                            Text(entry.note)
                                                .font(.footnote)
                                        }

                                        if !entry.evidenceFiles.isEmpty {
                                            Text("\(entry.evidenceFiles.count) evidence file(s)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }

                                if preview.entries.count > 20 {
                                    Text("Showing first 20 of \(preview.entries.count) entries.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Import Preview")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            viewModel.dismissImportPreview()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            Task {
                                await viewModel.confirmImport(for: rootViewModel.selectedYear)
                                await rootViewModel.selectYear(rootViewModel.selectedYear)
                            }
                        }
                        .disabled(!(viewModel.activeImportPreview?.isValid ?? false))
                    }
                }
            }
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

    private var allowedPackageTypes: [UTType] {
        #if os(macOS)
            [.directory]
        #else
            [.folder]
        #endif
    }
}
