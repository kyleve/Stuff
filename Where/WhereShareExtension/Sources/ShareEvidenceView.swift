import SwiftUI
import WhereCore
import WhereUI

/// The share-extension compose sheet: shows what was shared, lets the user pick
/// a kind, set the capture date, and add a note, then saves a new `Evidence`
/// into the shared store. Hosted by `ShareViewController`; `onSave`/`onCancel`
/// complete or cancel the extension request (there's no `@Environment(.dismiss)`
/// in an extension's root view controller).
struct ShareEvidenceView: View {
    @State private var model: ShareEvidenceModel
    private let onSave: () -> Void
    private let onCancel: () -> Void

    init(
        model: ShareEvidenceModel,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
    ) {
        _model = State(initialValue: model)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Group {
                switch model.phase {
                    case .loading:
                        ProgressView(String(localized: .shareLoading))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .composing, .saving, .failed:
                        ShareEvidenceForm(model: model)
                }
            }
            .animation(.default, value: model.phase)
            .navigationTitle(String(localized: .shareTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.shareCancel) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareEvidenceSaveButton(model: model, onSave: onSave)
                }
            }
            .alert(
                String(localized: .shareSaveErrorTitle),
                isPresented: $model.isShowingSaveError,
                presenting: model.saveErrorMessage,
            ) { _ in
                Button(.shareOk, role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
        .task { await model.loadAttachments() }
    }
}

private struct ShareEvidenceSaveButton: View {
    let model: ShareEvidenceModel
    let onSave: () -> Void

    var body: some View {
        Button(.shareSave) {
            Task {
                if await model.save() {
                    onSave()
                }
            }
        }
        .disabled(model.isSaving || model.phase == .loading)
    }
}

private struct ShareEvidenceForm: View {
    @Bindable var model: ShareEvidenceModel

    var body: some View {
        Form {
            ShareAttachmentSection(attachments: model.attachments)
            ShareEvidenceDetailsSection(model: model)
            ShareEvidenceNoteSection(note: $model.note)
        }
    }
}

private struct ShareAttachmentSection: View {
    let attachments: [SharedAttachment]

    var body: some View {
        Section {
            if attachments.isEmpty {
                Text(.shareAttachmentNone)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                    ShareAttachmentRow(attachment: attachment)
                }
            }
        } header: {
            Text(attachments.count > 1 ? .shareAttachmentHeaderPlural : .shareAttachmentHeader)
        }
    }
}

private struct ShareAttachmentRow: View {
    let attachment: SharedAttachment

    var body: some View {
        HStack {
            ShareAttachmentName(filename: attachment.filename)
            Spacer(minLength: 12)
            Text(attachment.data.count.formatted(.byteCount(style: .file)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct ShareAttachmentName: View {
    let filename: String?

    var body: some View {
        Label(
            filename ?? String(localized: .shareAttachmentFallbackName),
            systemSymbol: .paperclip,
        )
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

private struct ShareEvidenceDetailsSection: View {
    @Bindable var model: ShareEvidenceModel

    var body: some View {
        Section {
            ShareEvidenceKindPicker(kind: $model.kind)
            if case .other = model.kind {
                TextField(String(localized: .shareFormOtherLabel), text: $model.otherLabel)
            }
            DatePicker(String(localized: .shareFormDate), selection: $model.capturedAt)
        }
    }
}

private struct ShareEvidenceKindPicker: View {
    @Binding var kind: EvidenceKind

    var body: some View {
        Picker(String(localized: .shareFormKind), selection: $kind) {
            ForEach(EvidenceKind.knownCases, id: \.self) { kind in
                Label(kind.displayName, systemSymbol: kind.symbol).tag(kind)
            }
        }
    }
}

private struct ShareEvidenceNoteSection: View {
    @Binding var note: String

    var body: some View {
        Section {
            TextField(
                String(localized: .shareFormNotePlaceholder),
                text: $note,
                axis: .vertical,
            )
            .lineLimit(3, reservesSpace: true)
        } header: {
            Text(.shareFormNoteHeader)
        }
    }
}

#if DEBUG
    #Preview {
        ShareEvidenceView(
            model: ShareEvidenceModel(
                items: [],
                storage: .inMemory,
                compatibilityAccess: FixedDataCompatibilityAccess(receipt: .init(
                    domain: .local,
                    version: .current,
                    access: .verified,
                    removedDeviceID: nil,
                )),
            ),
            onSave: {},
            onCancel: {},
        )
    }
#endif
