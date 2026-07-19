import PeriscopeCore
import PhotosUI
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
                attachmentSection
                detailsSection
                noteSection
            }
            .navigationTitle(Strings.evidenceAdd)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.commonCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.evidenceSave) {
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
                Strings.evidenceSaveErrorTitle,
                isPresented: $model.isShowingSaveError,
                presenting: model.saveErrorMessage,
            ) { _ in
                Button(Strings.commonOK, role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert(
                Strings.evidenceSaveErrorTitle,
                isPresented: $model.isShowingAttachmentError,
                presenting: model.attachmentError,
            ) { _ in
                Button(Strings.commonOK, role: .cancel) {}
            } message: { message in
                Text(message)
            }
            // Log View Mode: reveal an inspect badge for this compose form's
            // events (attachment-pick / save). A no-op in release.
            .debugLogInspectable(WhereLog.evidence(AddEvidenceModelLog.self))
        }
    }

    private var attachmentSection: some View {
        Section {
            if let attachment = model.attachment {
                attachmentSummary(attachment)
                Button(role: .destructive) {
                    model.removeAttachment()
                    photoItem = nil
                } label: {
                    Label(Strings.evidenceRemoveAttachment, systemImage: "trash")
                }
            } else {
                Button {
                    showingFileImporter = true
                } label: {
                    Label(Strings.evidenceChooseFile, systemImage: "doc")
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(Strings.evidenceChoosePhoto, systemImage: "photo")
                }
            }
        } header: {
            Text(Strings.evidenceAttachmentHeader)
        }
    }

    private func attachmentSummary(_ attachment: PickedAttachment) -> some View {
        HStack {
            Label(
                attachment.filename ?? Strings.evidenceAttachmentHeader,
                systemImage: "paperclip",
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
            Picker(Strings.evidenceKindPickerLabel, selection: $model.kind) {
                ForEach(EvidenceKind.knownCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                }
            }
            if case .other = model.kind {
                TextField(Strings.evidenceOtherLabelPlaceholder, text: $model.otherLabel)
            }
            DatePicker(Strings.evidenceDateLabel, selection: $model.capturedAt)
        }
    }

    private var noteSection: some View {
        @Bindable var model = model
        return Section {
            TextField(
                Strings.evidenceNotePlaceholder,
                text: $model.note,
                axis: .vertical,
            )
            .lineLimit(3, reservesSpace: true)
        } header: {
            Text(Strings.evidenceNoteLabel)
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
                    model.reportAttachmentError(Strings.evidencePreviewFailed)
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
    #Preview {
        AddEvidenceView(model: PreviewSupport.addEvidenceModel())
    }
#endif
