import PeriscopeCore
import PhotosUI
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import UniformTypeIdentifiers
import WhereCore

/// In-app compose sheet for a new piece of evidence: pick an attachment (a file
/// or a photo), choose a kind, set the capture date, and add an optional note.
/// The attachment's content type is classified from its bytes/type identifier
/// on save. Presented from the evidence list's "+".
struct AddEvidenceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.stylesheet) private var stylesheet

    @State private var model: AddEvidenceModel
    @State private var showingFileImporter = false
    @State private var photoItem: PhotosPickerItem?

    init(report: YearReportModel) {
        _model = State(initialValue: AddEvidenceModel(
            services: report.services,
            now: report.now,
        ))
    }

    #if DEBUG
        /// Preview seam.
        init(model: AddEvidenceModel) {
            _model = State(initialValue: model)
        }
    #endif

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section {
                    composeHeader
                        .listRowBackground(stylesheet.palette.brand.raisedPaper)
                }
                attachmentSection
                detailsSection
                noteSection
            }
            .navigationTitle(String(localized: .evidenceAdd))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: .evidenceFormSave)) {
                        Task { if await model.save() { dismiss() } }
                    }
                    .disabled(model.isSaving)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                onCompletion: handleFileSelection,
            )
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .alert(
                String(localized: .evidenceFormSaveErrorTitle),
                isPresented: $model.isShowingSaveError,
                presenting: model.saveErrorMessage,
            ) { _ in
                Button(String(localized: .commonOk), role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert(
                String(localized: .evidenceFormSaveErrorTitle),
                isPresented: $model.isShowingAttachmentError,
                presenting: model.attachmentError,
            ) { _ in
                Button(String(localized: .commonOk), role: .cancel) {}
            } message: { message in
                Text(message)
            }
            // Log View Mode: reveal an inspect badge for this compose form's
            // events (attachment-pick / save). A no-op in release.
            .debugLogInspectable(WhereLog.evidence(AddEvidenceModelLog.self))
        }
    }

    private var composeHeader: some View {
        let compose = stylesheet.evidence.compose
        return HStack(alignment: .top, spacing: stylesheet.spacing.large) {
            VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                Text(String(localized: .evidenceFormDocumentLabel))
                    .font(compose.eyebrowFont)
                    .tracking(1.6)
                    .foregroundStyle(stylesheet.palette.brand.brass)
                Text(String(localized: .evidenceFormRecordTitle))
                    .font(compose.titleFont)
                    .foregroundStyle(stylesheet.palette.brand.ink)
                Text(String(localized: .evidenceFormRecordDetail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: stylesheet.spacing.medium)
            WhereSeal(tint: stylesheet.palette.brand.brass)
                .frame(width: compose.sealSize)
        }
        .accessibilityElement(children: .combine)
    }

    private var attachmentSection: some View {
        Section {
            if let attachment = model.attachment {
                attachmentSummary(attachment)
                Button(role: .destructive) {
                    model.removeAttachment()
                    photoItem = nil
                } label: {
                    Label(String(localized: .evidenceFormRemove), systemSymbol: .trash)
                }
            } else {
                Button {
                    showingFileImporter = true
                } label: {
                    Label(String(localized: .evidenceFormChooseFile), systemSymbol: .doc)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(String(localized: .evidenceFormChoosePhoto), systemSymbol: .photo)
                }
            }
        } header: {
            Text(String(localized: .evidenceFormAttachmentHeader))
        }
    }

    private func attachmentSummary(_ attachment: PickedAttachment) -> some View {
        HStack {
            Label(
                attachment.filename ?? String(localized: .evidenceFormAttachmentHeader),
                systemSymbol: .paperclip,
            )
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: stylesheet.spacing.medium)
            Text(attachment.data.count.formatted(.byteCount(style: .file)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var detailsSection: some View {
        @Bindable var model = model
        return Section {
            Picker(String(localized: .evidenceFormKind), selection: $model.kind) {
                ForEach(EvidenceKind.knownCases, id: \.self) { kind in
                    Label(kind.displayName, systemSymbol: kind.symbol).tag(kind)
                }
            }
            if case .other = model.kind {
                TextField(String(localized: .evidenceFormOtherLabel), text: $model.otherLabel)
            }
            DatePicker(String(localized: .evidenceFormDate), selection: $model.capturedAt)
        }
    }

    private var noteSection: some View {
        @Bindable var model = model
        return Section {
            TextField(
                String(localized: .evidenceFormNotePlaceholder),
                text: $model.note,
                axis: .vertical,
            )
            .lineLimit(3, reservesSpace: true)
        } header: {
            Text(String(localized: .evidenceFormNote))
        }
    }

    private func handleFileSelection(_ result: Result<URL, any Error>) {
        switch result {
            case let .success(url):
                readFile(at: url)
            case let .failure(error):
                model.reportAttachmentError(error.localizedDescription)
        }
    }

    /// Read a security-scoped file URL into memory and attach it. Access is
    /// scoped for the read only — the bytes are copied into the store, so the
    /// original file is never referenced again. The read runs off the main actor
    /// so a large file doesn't block the UI; the cheap metadata is read up front
    /// while the scope is active.
    private func readFile(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        let typeIdentifier = (try? url.resourceValues(forKeys: [.contentTypeKey]))?
            .contentType?.identifier
        let filename = url.lastPathComponent
        Task {
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url)
                }.value
                model.setAttachment(PickedAttachment(
                    data: data,
                    typeIdentifier: typeIdentifier,
                    filename: filename,
                ))
            } catch {
                model.reportAttachmentError(error.localizedDescription)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    model.reportAttachmentError(String(localized: .evidenceDetailPreviewFailed))
                    return
                }
                model.setAttachment(PickedAttachment(
                    data: data,
                    typeIdentifier: item.supportedContentTypes.first?.identifier,
                    filename: nil,
                ))
            } catch {
                model.reportAttachmentError(error.localizedDescription)
            }
        }
    }
}

#if DEBUG
    extension AddEvidenceView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Compose",
                configurations: .fullContentScreenDefaults + [
                    SnapshotConfiguration(
                        layoutDirection: .rightToLeft,
                        device: .iPhoneFullContent,
                    ),
                ],
                settle: .immediate,
            ) {
                AddEvidenceView(model: PreviewSupport.addEvidenceModel())
            }
        }
    }

    #Preview {
        AddEvidenceView.snapshotPreviews
    }
#endif

#if DEBUG
    extension AddEvidenceView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            AddEvidenceView.self,
            title: "Add Evidence",
        ) { _ in
            AddEvidenceView(model: PreviewSupport.addEvidenceModel())
        }
    }
#endif
