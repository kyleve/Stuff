import PatchlightCore
import SwiftUI

struct PatchlightConversationView: View {
    let model: PatchlightAppModel
    @State private var commentBody = ""

    var body: some View {
        Group {
            switch model.reviewState {
                case .none, .loading:
                    ProgressView(String(
                        localized: "loadingConversation",
                        defaultValue: "Loading conversation…",
                    ))
                case let .ready(read, _):
                    conversation(read)
                case let .failed(cached, _, message):
                    if let cached {
                        conversation(cached)
                            .safeAreaInset(edge: .top) { failure(message) }
                    } else {
                        ContentUnavailableView(
                            String(
                                localized: "couldNotLoadConversation",
                                defaultValue: "Could Not Load Conversation",
                            ),
                            systemImage: "exclamationmark.triangle",
                            description: Text(message),
                        )
                    }
            }
        }
    }

    private func conversation(_ read: ConversationRead) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let reason = read.fallbackReason {
                    Label(reason.message, systemImage: "icloud.slash")
                        .patchlightConversationBanner(color: .orange)
                }
                immediateStatus
                checks(read.value.checks)
                ForEach(read.value.issueComments) { comment in
                    CommentCard(comment: comment)
                }
                ForEach(read.value.reviews) { review in
                    ReviewCard(review: review)
                }
                ForEach(read.value.threads) { thread in
                    ThreadCard(
                        thread: thread,
                        onReply: { commentID, body in
                            await model.reply(to: commentID, body: body)
                        },
                        onSetResolved: { resolved in
                            await model.setThread(thread.id, resolved: resolved)
                        },
                    )
                }
                commentComposer
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .refreshable { await model.refreshReview() }
    }

    @ViewBuilder
    private func checks(_ checks: [CheckSummary]) -> some View {
        if !checks.isEmpty {
            GroupBox(String(localized: "checks", defaultValue: "Checks")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(checks) { check in
                        HStack {
                            Image(systemName: symbol(for: check.state))
                                .foregroundStyle(color(for: check.state))
                            if let url = check.detailsURL {
                                Link(check.name, destination: url)
                            } else {
                                Text(check.name)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var commentComposer: some View {
        GroupBox(String(
            localized: "newConversationComment",
            defaultValue: "New Conversation Comment",
        )) {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $commentBody)
                    .frame(minHeight: 100)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).stroke(.separator)
                    }
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
                Button(String(localized: "sendComment", defaultValue: "Send Comment")) {
                    let body = commentBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    commentBody = ""
                    Task { await model.postConversationComment(body) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var immediateStatus: some View {
        switch model.immediateWriteState {
            case .idle:
                EmptyView()
            case .sending:
                ProgressView(String(localized: "sending", defaultValue: "Sending…"))
            case let .sent(reconciled):
                Label(
                    reconciled
                        ? String(
                            localized: "reconciledSubmission",
                            defaultValue: "GitHub confirmed the write after reconciliation.",
                        )
                        : String(localized: "commentSent", defaultValue: "Comment sent."),
                    systemImage: "checkmark.circle",
                )
                .patchlightConversationBanner(color: .green)
            case let .uncertain(requestID):
                Label(
                    uncertainMessage(requestID),
                    systemImage: "questionmark.circle",
                )
                .patchlightConversationBanner(color: .orange)
            case let .failed(message):
                failure(message)
        }
    }

    private func failure(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .patchlightConversationBanner(color: .red)
    }

    private func uncertainMessage(_ requestID: String?) -> String {
        if let requestID {
            return String(
                localized: "writeUncertainRequest",
                defaultValue: "Submission status is uncertain (request \(requestID)). Refresh before trying again.",
            )
        }
        return String(
            localized: "writeUncertain",
            defaultValue: "Submission status is uncertain. Refresh before trying again.",
        )
    }

    private func symbol(for state: CheckState) -> String {
        switch state {
            case .pending: "clock"
            case .success: "checkmark.circle.fill"
            case .failure: "xmark.circle.fill"
            case .neutral: "minus.circle"
            case .skipped: "forward.circle"
        }
    }

    private func color(for state: CheckState) -> Color {
        switch state {
            case .pending: .orange
            case .success: .green
            case .failure: .red
            case .neutral, .skipped: .secondary
        }
    }
}

private struct CommentCard: View {
    let comment: ConversationComment

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(comment.authorLogin).font(.headline)
                    Spacer()
                    Text(comment.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                markdown(comment.bodyMarkdown)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReviewCard: View {
    let review: PullRequestReview

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(review.authorLogin, systemImage: symbol)
                    Spacer()
                    if let submittedAt = review.submittedAt {
                        Text(submittedAt, style: .relative)
                    }
                }
                .font(.headline)
                if !review.bodyMarkdown.isEmpty {
                    markdown(review.bodyMarkdown).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var symbol: String {
        switch review.state {
            case .approved: "checkmark.circle"
            case .changesRequested: "xmark.circle"
            case .commented: "bubble.left"
            case .dismissed: "slash.circle"
            case .pending: "clock"
        }
    }
}

private struct ThreadCard: View {
    let thread: ReviewThread
    let onReply: (GitHubCommentID, String) async -> Void
    let onSetResolved: (Bool) async -> Void
    @State private var replyBody = ""

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        "\(thread.path):\(thread.line.map(String.init) ?? "–")",
                        systemImage: "text.bubble",
                    )
                    if thread.isOutdated {
                        Text(String(localized: "outdated", defaultValue: "Outdated"))
                            .foregroundStyle(.orange)
                    }
                    if thread.isResolved {
                        Text(String(localized: "resolved", defaultValue: "Resolved"))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    if thread.canResolve {
                        Button(
                            thread.isResolved
                                ? String(localized: "unresolve", defaultValue: "Unresolve")
                                : String(localized: "resolve", defaultValue: "Resolve"),
                        ) {
                            Task { await onSetResolved(!thread.isResolved) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                ForEach(thread.comments) { comment in
                    CommentCard(comment: comment)
                }
                if let commentID = thread.comments.last?.databaseID {
                    TextEditor(text: $replyBody)
                        .frame(minHeight: 72)
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
                        .accessibilityLabel(String(
                            localized: "replyBody",
                            defaultValue: "Reply body",
                        ))
                    HStack {
                        Label(
                            String(
                                localized: "replyPostsImmediately",
                                defaultValue: "Replies post immediately.",
                            ),
                            systemImage: "paperplane",
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "sendReply", defaultValue: "Send Reply")) {
                            let body = replyBody.trimmingCharacters(in: .whitespacesAndNewlines)
                            replyBody = ""
                            Task { await onReply(commentID, body) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func markdown(_ source: String) -> Text {
    (try? AttributedString(markdown: source)).map(Text.init) ?? Text(source)
}

extension View {
    fileprivate func patchlightConversationBanner(color: Color) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}
