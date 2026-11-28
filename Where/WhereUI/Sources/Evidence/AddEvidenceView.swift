import PeriscopeCore
import PhotosUI
import SFSafeSymbols
import SwiftUI
import UniformTypeIdentifiers
import WhereCore

/// In-app compose sheet for a new piece of evidence: pick an attachment (a file
/// or a photo), choose a kind, set the capture date, and add an optional note.
/// The attachment's content type is classified from its bytes/type identifier
/// on save. Presented from the evidence list's "+".
struct AddEvidenceView: View {
    @Environment(\.dismiss) private var dismiss

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
                EvidenceAttachmentSection(
                    attachment: model.attachment,
                    photoItem: $photoItem,
                    chooseFile: { showingFileImporter = true },
                    remove: {
                        model.removeAttachment()
                        photoItem = nil
                    },
                )
                EvidenceDetailsSection(model: model)
                EvidenceNoteSection(note: $model.note)
            }
            .navigationTitle(String(localized: .evidenceAdd))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SaveEvidenceButton(isSaving: model.isSaving) {
                        Task {
                            if await model.save() {
                                dismiss()
                            }
                        }
                    }
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

    private func handleFileSelection(_ result: Result<URL, any Error>) {
        switch result {
            case let .success(url):
                readFile(at: url)
            case let .failure(error):
                model.reportAttachmentError(error)
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
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
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
                model.reportAttachmentError(error)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AddEvidenceModel.AttachmentFailure.unavailablePhotoData
                }
                model.setAttachment(PickedAttachment(
                    data: data,
                    typeIdentifier: item.supportedContentTypes.first?.identifier,
                    filename: nil,
                ))
            } catch {
                model.reportAttachmentError(error)
            }
        }
    }
}

private struct SaveEvidenceButton: View {
    let isSaving: Bool
    let save: () -> Void

    var body: some View {
        Button(String(localized: .evidenceFormSave), action: save)
            .disabled(isSaving)
    }
}

private struct EvidenceAttachmentSection: View {
    let attachment: PickedAttachment?
    @Binding var photoItem: PhotosPickerItem?
    let chooseFile: () -> Void
    let remove: () -> Void

    var body: some View {
        Section {
            if let attachment {
                EvidenceAttachmentSummary(attachment: attachment)
                RemoveEvidenceAttachmentButton(remove: remove)
            } else {
                ChooseEvidenceFileButton(choose: chooseFile)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(String(localized: .evidenceFormChoosePhoto), systemSymbol: .photo)
                }
            }
        } header: {
            Text(String(localized: .evidenceFormAttachmentHeader))
        }
    }
}

private struct EvidenceAttachmentSummary: View {
    let attachment: PickedAttachment
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
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
}

private struct RemoveEvidenceAttachmentButton: View {
    let remove: () -> Void

    var body: some View {
        Button(role: .destructive) {
            remove()
        } label: {
            Label(String(localized: .evidenceFormRemove), systemSymbol: .trash)
        }
    }
}

private struct ChooseEvidenceFileButton: View {
    let choose: () -> Void

    var body: some View {
        Button {
            choose()
        } label: {
            Label(String(localized: .evidenceFormChooseFile), systemSymbol: .doc)
        }
    }
}

private struct EvidenceDetailsSection: View {
    @Bindable var model: AddEvidenceModel

    var body: some View {
        Section {
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
}

private struct EvidenceNoteSection: View {
    @Binding var note: String

    var body: some View {
        Section {
            TextField(
                String(localized: .evidenceFormNotePlaceholder),
                text: $note,
                axis: .vertical,
            )
            .lineLimit(3, reservesSpace: true)
        } header: {
            Text(String(localized: .evidenceFormNote))
        }
    }
}

#if DEBUG
    #Preview {
        AddEvidenceView(model: PreviewSupport.addEvidenceModel())
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
