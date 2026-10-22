import SnapshotReviewCore
import SwiftUI

struct ReviewDetailsView: View {
    @Bindable var model: ReviewBrowserModel
    let image: SnapshotImage
    @Environment(\.reviewStyle) private var style

    var body: some View {
        Form {
            Section("Snapshot") {
                Text(image.id.path.value).font(.caption.monospaced()).textSelection(.enabled)
                if case let .success(content) = image.content {
                    LabeledContent(
                        "Dimensions",
                        value: "\(content.pixels.width) × \(content.pixels.height)",
                    )
                    LabeledContent("Modified") { Text(content.modifiedAt, format: .dateTime) }
                }
                if let review = model.review(image) {
                    if let revision = review.reviewed {
                        LabeledContent("Last reviewed") { Text(revision.date, format: .dateTime) }
                    }
                    Text(model.needsReview(image) ? "Needs review" : "Reviewed")
                    Text("\(review.openTodoCount) open todos")
                    Button(model.needsReview(image) ? "Mark Reviewed" : "Mark Unreviewed") {
                        Task { _ = await model.markReviewed(
                            image,
                            reviewed: model.needsReview(image),
                        ) }
                    }
                } else {
                    Text("Review file unavailable. Refresh after fixing the file.")
                        .foregroundStyle(.red)
                }
            }
            Section("Annotations") {
                HStack {
                    Button("Add Note") { model.beginAnnotation(point: nil) }
                    Button(model.placement == nil ? "Add Point" : "Cancel Point") {
                        model.placement = model.placement == nil ? .newPoint : nil
                    }
                }
                ForEach(model.review(image)?.annotations ?? []) { annotation in
                    annotationRow(annotation)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isBusy || !model.canReviewDisplayedImage)
    }

    private func annotationRow(_ annotation: ReviewAnnotation) -> some View {
        VStack(alignment: .leading) {
            Button {
                model.selectedAnnotation = annotation.id
            } label: {
                VStack(alignment: .leading) {
                    Text(annotation.text).multilineTextAlignment(.leading)
                    Text(annotation.status.rawValue
                        .capitalized + (annotation.point == nil ? " · Whole image" : " · Point"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            if case let .success(content) = image.content,
               annotation.fingerprint != content.fingerprint
            {
                Text("Written against an older image").font(.caption).foregroundStyle(.orange)
                if annotation.point != nil {
                    Button("Confirm Point") {
                        var updated = annotation
                        updated.fingerprint = content.fingerprint
                        updated.editedAt = Date()
                        Task { await model.updateAnnotation(updated, image: image) }
                    }
                }
            }
            HStack {
                Button("Edit") { model.draft = .init(image: image, annotation: annotation) }
                if annotation
                    .point != nil { Button("Move") { model.placement = .move(annotation.id) } }
                if annotation.status != .note {
                    Button(annotation.status == .open ? "Resolve" : "Reopen") {
                        var updated = annotation
                        updated.status = annotation.status == .open ? .resolved : .open
                        updated.editedAt = Date()
                        Task { await model.updateAnnotation(updated, image: image) }
                    }
                }
                Button("Delete", role: .destructive) { Task { await model.deleteAnnotation(
                    annotation,
                    image: image,
                ) } }
            }.font(.caption)
        }
        .padding(.vertical, style.details.rowPadding)
    }
}

struct ReviewAnnotationEditor: View {
    @Bindable var model: ReviewBrowserModel
    @State var draft: AnnotationDraft
    @Environment(\.reviewStyle) private var style
    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $draft.annotation.status) {
                    Text("Note").tag(ReviewAnnotation.Status.note)
                    Text("Open Todo").tag(ReviewAnnotation.Status.open)
                    Text("Resolved Todo").tag(ReviewAnnotation.Status.resolved)
                }
                TextEditor(text: $draft.annotation.text)
                    .frame(minHeight: style.details.editorMinimumHeight)
                    .accessibilityLabel("Annotation text")
                if let error = model.error {
                    Text(error.localizedDescription).foregroundStyle(.red)
                    Button("Reload Files and Keep Draft") {
                        Task { draft = await model.reloadDraft(draft) }
                    }
                }
            }
            .navigationTitle("Annotation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.draft = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.draft = draft; Task { await model.saveDraft() } }
                        .disabled(draft.annotation.text
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model
                            .isBusy)
                }
            }
        }
    }
}

#if DEBUG
    import BroadwayUI
    import SnapshotKit

    extension ReviewDetailsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Annotations",
                configurations: [.init(device: .iPhoneFullContent)],
                settle: .settledAtLeast(minDuration: 0.3),
            ) {
                let model = ReviewPreviewFixtures.model(loaded: true, single: true)
                if let image = model.selectedImage {
                    NavigationStack {
                        ReviewDetailsView(model: model, image: image)
                            .navigationTitle("Snapshot Details")
                    }.broadwayRoot()
                }
            }
        }
    }

    #Preview { ReviewDetailsView.snapshotPreviews }
#endif
