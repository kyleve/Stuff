import PatchlightCore
import SwiftUI

struct PatchlightReviewComposer: View {
    @Environment(\.dismiss) private var dismiss
    let model: PatchlightAppModel
    @State private var event = ReviewEvent.comment
    @State private var summary = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "reviewAction", defaultValue: "Review Action")) {
                    Picker(
                        String(localized: "reviewAction", defaultValue: "Review Action"),
                        selection: $event,
                    ) {
                        Text(String(localized: "comment", defaultValue: "Comment"))
                            .tag(ReviewEvent.comment)
                        Text(String(localized: "approve", defaultValue: "Approve"))
                            .tag(ReviewEvent.approve)
                            .disabled(!model.canSubmit(.approve))
                        Text(String(localized: "requestChanges", defaultValue: "Request Changes"))
                            .tag(ReviewEvent.requestChanges)
                            .disabled(!model.canSubmit(.requestChanges))
                    }
                    .pickerStyle(.segmented)
                    if !model.canSubmit(.approve) {
                        Text(String(
                            localized: "ownPullRequestReviewLimitation",
                            defaultValue: "GitHub does not allow approving or requesting changes on your own pull request.",
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "reviewSummary", defaultValue: "Review Summary")) {
                    TextEditor(text: $summary)
                        .frame(minHeight: 140)
                }
                Section(String(localized: "draftComments", defaultValue: "Draft Comments")) {
                    if model.reviewDrafts.isEmpty {
                        Text(String(
                            localized: "noDraftComments",
                            defaultValue: "No line or file drafts.",
                        ))
                        .foregroundStyle(.secondary)
                    }
                    ForEach(model.reviewDrafts) { draft in
                        VStack(alignment: .leading) {
                            Text(draft.anchor?.path ?? String(
                                localized: "reviewSummary",
                                defaultValue: "Review Summary",
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(draft.body)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "submitReview", defaultValue: "Submit Review"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .cancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "submit", defaultValue: "Submit")) {
                        Task {
                            await model.submitReview(event: event, summary: summary)
                            if case .sent = model.submissionState { dismiss() }
                        }
                    }
                    .disabled(!model.canSubmit(event))
                }
            }
        }
    }
}

struct PatchlightDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    let anchor: DiffAnchor
    let model: PatchlightAppModel
    @State private var draftBody = ""

    var content: some View {
        NavigationStack {
            Form {
                LabeledContent(String(localized: "file", defaultValue: "File"), value: anchor.path)
                LabeledContent(
                    String(localized: "line", defaultValue: "Line"),
                    value: anchor.line.map(String.init) ?? String(
                        localized: "fileLevel",
                        defaultValue: "File level",
                    ),
                )
                TextEditor(text: $draftBody)
                    .frame(minHeight: 160)
                    .accessibilityLabel(String(
                        localized: "draftComment",
                        defaultValue: "Draft comment",
                    ))
            }
            .navigationTitle(String(localized: "addReviewDraft", defaultValue: "Add Review Draft"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .cancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "saveDraft", defaultValue: "Save Draft")) {
                        Task {
                            await model.saveDraft(anchor: anchor, body: draftBody)
                            dismiss()
                        }
                    }
                    .disabled(draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    var body: some View {
        content
    }
}

struct PatchlightFileCommentComposer: View {
    @Environment(\.dismiss) private var dismiss
    let path: String
    let model: PatchlightAppModel
    @State private var commentBody = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(String(localized: "file", defaultValue: "File"), value: path)
                TextEditor(text: $commentBody)
                    .frame(minHeight: 180)
                    .accessibilityLabel(String(
                        localized: "commentBody",
                        defaultValue: "Comment body",
                    ))
                Label(
                    String(
                        localized: "postsImmediately",
                        defaultValue: "This posts immediately and is not part of the review batch.",
                    ),
                    systemImage: "paperplane",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(String(localized: "fileComment", defaultValue: "File Comment"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .cancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "send", defaultValue: "Send")) {
                        Task {
                            await model.postFileComment(commentBody, path: path)
                            dismiss()
                        }
                    }
                    .disabled(commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
