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
                        ProgressView(ShareStrings.loading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .composing, .saving, .failed:
                        form
                }
            }
            .animation(.default, value: model.phase)
            .navigationTitle(ShareStrings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ShareStrings.cancel) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ShareStrings.save) {
                        Task { if await model.save() { onSave() } }
                    }
                    .disabled(model.isSaving || model.phase == .loading)
                }
            }
            .alert(
                ShareStrings.saveErrorTitle,
                isPresented: $model.isShowingSaveError,
                presenting: model.saveErrorMessage,
            ) { _ in
                Button(ShareStrings.ok, role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
        .task { await model.loadAttachments() }
    }

    private var form: some View {
        @Bindable var model = model

        return Form {
            attachmentSection
            Section {
                Picker(ShareStrings.kindLabel, selection: $model.kind) {
                    ForEach(EvidenceKind.knownCases, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                    }
                }
                if case .other = model.kind {
                    TextField(ShareStrings.otherLabelPlaceholder, text: $model.otherLabel)
                }
                DatePicker(ShareStrings.dateLabel, selection: $model.capturedAt)
            }
            Section {
                TextField(
                    ShareStrings.notePlaceholder,
                    text: $model.note,
                    axis: .vertical,
                )
                .lineLimit(3, reservesSpace: true)
            } header: {
                Text(ShareStrings.noteHeader)
            }
        }
    }

    private var attachmentSection: some View {
        Section {
            if model.attachments.isEmpty {
                Text(ShareStrings.noAttachment)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.attachments.enumerated()), id: \.offset) { _, attachment in
                    attachmentRow(attachment)
                }
            }
        } header: {
            Text(ShareStrings.attachmentHeader(count: model.attachments.count))
        }
    }

    private func attachmentRow(_ attachment: SharedAttachment) -> some View {
        HStack {
            Label(
                attachment.filename ?? ShareStrings.attachmentFallbackName,
                systemImage: "paperclip",
            )
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(attachment.data.count.formatted(.byteCount(style: .file)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

#if DEBUG
    #Preview {
        ShareEvidenceView(
            model: ShareEvidenceModel(items: [], storage: .inMemory),
            onSave: {},
            onCancel: {},
        )
    }
#endif
