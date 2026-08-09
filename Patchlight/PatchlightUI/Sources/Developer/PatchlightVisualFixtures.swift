#if DEBUG
    import Foundation
    import PatchlightCore
    import UIKit

    /// Deterministic product data shared by Patchlight previews and visual acceptance tests.
    @MainActor
    enum PatchlightVisualFixtures {
        static let repositoryID = RepositoryID(rawValue: 77)
        static let coordinates = RepositoryCoordinates(owner: "acme", name: "Patchlight")
        static let pullRequestID = PullRequestID(repository: repositoryID, number: 142)
        static let baseOID = GitObjectID(rawValue: String(repeating: "a", count: 40))
        static let headOID = GitObjectID(rawValue: String(repeating: "b", count: 40))
        static let snapshotBaseOID = GitObjectID(rawValue: String(repeating: "c", count: 40))
        static let snapshotHeadOID = GitObjectID(rawValue: String(repeating: "d", count: 40))

        static var summary: PullRequestSummary {
            PullRequestSummary(
                id: pullRequestID,
                repository: coordinates,
                title: "Protect account vault rotation",
                authorLogin: "alex",
                isDraft: false,
                headOID: headOID,
                createdAt: Date.now.addingTimeInterval(-86400),
                updatedAt: Date.now.addingTimeInterval(-1800),
                reviewRequestSource: .direct,
                actionability: .newActivity,
            )
        }

        static var dashboardContent: PatchlightDashboardContent {
            let teamRequest = pullRequest(
                number: 138,
                title: "Refresh snapshot fixtures",
                author: "morgan",
                source: .team(organization: "acme", slug: "ios"),
                actionability: .teamRequest,
                headCharacter: "e",
            )
            let unresolved = pullRequest(
                number: 137,
                title: "Repair migration rollback",
                author: "sam",
                source: .direct,
                actionability: .unresolvedThreads,
                headCharacter: "f",
            )
            let ownDraft = pullRequest(
                number: 141,
                title: "Polish repository settings",
                author: "reviewer",
                isDraft: true,
                source: nil,
                actionability: .draft,
                headCharacter: "1",
            )
            let repository = RepositorySummary(
                id: repositoryID,
                coordinates: coordinates,
                installationID: GitHubInstallationID(rawValue: 19),
                isPrivate: true,
                defaultBranch: "main",
            )
            return content(ReviewDashboard(
                viewer: viewer,
                reviewRequests: [summary, teamRequest, unresolved],
                ownPullRequests: [ownDraft],
                installations: [GitHubInstallationSummary(
                    id: GitHubInstallationID(rawValue: 19),
                    accountLogin: "acme",
                    accountType: .organization,
                    repositories: [repository],
                    teamDiscovery: .available,
                )],
                warnings: [],
            ))
        }

        static var emptyDashboardContent: PatchlightDashboardContent {
            content(ReviewDashboard(
                viewer: viewer,
                reviewRequests: [],
                ownPullRequests: [],
                installations: [],
                warnings: [],
            ))
        }

        static var workspaceContent: PatchlightWorkspaceContent {
            PatchlightWorkspaceContent(
                workspace: workspace,
                source: .live,
                refreshedAt: .now,
                fallbackReason: nil,
            )
        }

        static var workspace: PullRequestWorkspace {
            PullRequestWorkspace(
                summary: summary,
                bodyMarkdown: "Rotates each account vault key atomically and keeps drafts readable during reauthorization.",
                baseOID: baseOID,
                files: [riskFile, hiddenFile, snapshotFile],
                isFileListComplete: true,
                repositoryConfiguration: .absent,
            )
        }

        static var reviewPlan: DeterministicReviewPlan {
            DeterministicReviewPlan(
                files: [
                    FileReviewPlan(
                        file: riskFile,
                        minimumDepth: .critical,
                        hunks: [hunkPlan(
                            riskFile.hunks[0],
                            depth: .critical,
                            category: .risk,
                            partial: true,
                        )],
                        isSnapshot: false,
                    ),
                    FileReviewPlan(
                        file: hiddenFile,
                        minimumDepth: .everything,
                        hunks: [hunkPlan(
                            hiddenFile.hunks[0],
                            depth: .everything,
                            category: .generated,
                            partial: false,
                        )],
                        isSnapshot: false,
                    ),
                    FileReviewPlan(
                        file: snapshotFile,
                        minimumDepth: .critical,
                        hunks: [],
                        isSnapshot: true,
                    ),
                ],
                configurationWarning: nil,
            )
        }

        static var settings: PatchlightRepositorySettings {
            PatchlightRepositorySettings(
                repository: repositoryID,
                aiEnabled: false,
                imageAIEnabled: false,
                overrides: .empty,
            )
        }

        static var conversation: ConversationRead {
            let annotation = SnapshotAnnotationV1(
                path: snapshotFile.path,
                target: .head,
                blobOID: snapshotHeadOID,
                rectangle: rectangle(x: 0.58, y: 0.16, width: 0.25, height: 0.22),
                sourceWidth: 640,
                sourceHeight: 420,
                tag: .problem,
            )
            let annotationBody = "The new card clips at larger text sizes.\n\n\(marker(annotation))"
            let threadComment = ConversationComment(
                id: GitHubNodeID(rawValue: "thread-comment-1"),
                databaseID: GitHubCommentID(rawValue: 501),
                authorLogin: "morgan",
                bodyMarkdown: "Could this decrypt after the replacement key is durably stored?",
                createdAt: Date.now.addingTimeInterval(-1200),
                kind: .reply,
            )
            return ConversationRead(
                value: PullRequestConversation(
                    pullRequest: PullRequestRoute(summary: summary),
                    headOID: headOID,
                    issueComments: [
                        ConversationComment(
                            id: GitHubNodeID(rawValue: "issue-comment-1"),
                            databaseID: GitHubCommentID(rawValue: 502),
                            authorLogin: "alex",
                            bodyMarkdown: "The failure path now preserves the previous encrypted payload.",
                            createdAt: Date.now.addingTimeInterval(-3600),
                            kind: .issue,
                        ),
                        ConversationComment(
                            id: GitHubNodeID(rawValue: "snapshot-comment-1"),
                            databaseID: GitHubCommentID(rawValue: 503),
                            authorLogin: "reviewer",
                            bodyMarkdown: annotationBody,
                            createdAt: Date.now.addingTimeInterval(-900),
                            kind: .issue,
                        ),
                    ],
                    reviews: [PullRequestReview(
                        id: GitHubNodeID(rawValue: "review-1"),
                        authorLogin: "morgan",
                        bodyMarkdown: "Please cover interrupted rotation.",
                        state: .changesRequested,
                        submittedAt: Date.now.addingTimeInterval(-7200),
                    )],
                    threads: [ReviewThread(
                        id: GitHubNodeID(rawValue: "thread-1"),
                        path: riskFile.path,
                        line: 42,
                        side: .head,
                        isOutdated: true,
                        isResolved: false,
                        canResolve: true,
                        comments: [threadComment],
                    )],
                    checks: [
                        CheckSummary(name: "PatchlightCoreTests", state: .success, detailsURL: nil),
                        CheckSummary(name: "Catalyst", state: .pending, detailsURL: nil),
                        CheckSummary(name: "Snapshots", state: .failure, detailsURL: nil),
                    ],
                ),
                source: .live,
                refreshedAt: .now,
                fallbackReason: nil,
            )
        }

        static var drafts: [ReviewDraft] {
            [
                ReviewDraft(
                    id: uuid("4C12E763-0C5D-4F43-BEA5-A42A03196D41"),
                    pullRequest: pullRequestID,
                    anchor: anchor(line: 42),
                    body: "Keep the old key until the replacement write succeeds.",
                    updatedAt: .now,
                ),
                ReviewDraft(
                    id: uuid("7C4E60D2-1633-4CD2-8654-5127A83332EA"),
                    pullRequest: pullRequestID,
                    anchor: DiffAnchor(
                        path: hiddenFile.path,
                        side: .head,
                        commitOID: headOID,
                        blobOID: hiddenFile.headBlobOID,
                        line: 2,
                        startLine: nil,
                        contextFingerprint: "generated-context",
                    ),
                    body: "This generated change is expected.",
                    updatedAt: .now,
                ),
            ]
        }

        static var staleResults: [DraftAnchorMapper.Result] {
            [
                DraftAnchorMapper.Result(
                    draft: drafts[0],
                    resolution: .ambiguous(candidateCount: 2),
                ),
                DraftAnchorMapper.Result(draft: drafts[1], resolution: .deleted),
            ]
        }

        static var snapshotPair: SnapshotImagePair {
            SnapshotImagePair(
                file: snapshotFile,
                base: SnapshotImageAsset(
                    oid: snapshotBaseOID,
                    data: png(size: CGSize(width: 640, height: 420), variant: .base),
                ),
                head: SnapshotImageAsset(
                    oid: snapshotHeadOID,
                    data: png(size: CGSize(width: 640, height: 420), variant: .head),
                ),
                comparison: .comparable(
                    metrics: SnapshotDiffMetrics(
                        dimensions: SnapshotDimensions(width: 640, height: 420),
                        changedPixels: 18420,
                        changedFraction: 0.0685,
                        maximumChannelDelta: 184,
                        changedBounds: CGRect(x: 360, y: 66, width: 174, height: 98),
                    ),
                    heatmapPNGData: png(
                        size: CGSize(width: 640, height: 420),
                        variant: .heatmap,
                    ),
                ),
            )
        }

        static var mismatchedSnapshotPair: SnapshotImagePair {
            SnapshotImagePair(
                file: snapshotFile,
                base: SnapshotImageAsset(
                    oid: snapshotBaseOID,
                    data: png(size: CGSize(width: 640, height: 420), variant: .base),
                ),
                head: SnapshotImageAsset(
                    oid: snapshotHeadOID,
                    data: png(size: CGSize(width: 700, height: 420), variant: .head),
                ),
                comparison: .dimensionMismatch(
                    base: SnapshotDimensions(width: 640, height: 420),
                    head: SnapshotDimensions(width: 700, height: 420),
                ),
            )
        }

        static func dashboardModel(_ state: PatchlightAppModel.AccountState) -> PatchlightAppModel {
            let model = PatchlightAppModel(dependencies: .preview)
            model.installFixture(.account(state))
            return model
        }

        static func workspaceModel(
            submission: PatchlightAppModel.SubmissionState = .idle,
            immediateWrite: PatchlightAppModel.ImmediateWriteState = .idle,
            snapshot: PatchlightAppModel.SnapshotState = .none,
        ) -> PatchlightAppModel {
            let model = PatchlightAppModel(dependencies: .preview)
            model.installFixture(.workspace(
                dashboard: dashboardContent,
                content: workspaceContent,
                review: .ready(conversation, drafts: drafts),
                submission: submission,
                immediateWrite: immediateWrite,
                reviewPlan: reviewPlan,
                settings: settings,
                snapshot: snapshot,
                imageAnalysis: .idle,
            ))
            return model
        }

        private static var viewer: GitHubViewer {
            GitHubViewer(
                id: PatchlightAccountID(rawValue: 88),
                login: "reviewer",
                avatarURL: nil,
            )
        }

        private static func content(_ dashboard: ReviewDashboard) -> PatchlightDashboardContent {
            PatchlightDashboardContent(CachedRead(
                value: dashboard,
                source: .live,
                refreshedAt: .now,
                fallbackReason: nil,
            ))
        }

        private static func pullRequest(
            number: Int,
            title: String,
            author: String,
            isDraft: Bool = false,
            source: ReviewRequestSource?,
            actionability: ReviewActionability,
            headCharacter: Character,
        ) -> PullRequestSummary {
            PullRequestSummary(
                id: PullRequestID(repository: repositoryID, number: number),
                repository: coordinates,
                title: title,
                authorLogin: author,
                isDraft: isDraft,
                headOID: GitObjectID(rawValue: String(repeating: headCharacter, count: 40)),
                createdAt: Date.now.addingTimeInterval(-172_800),
                updatedAt: Date.now.addingTimeInterval(-3600),
                reviewRequestSource: source,
                actionability: actionability,
            )
        }

        private static var riskFile: DiffFile {
            DiffFile(
                path: "Patchlight/PatchlightCore/Sources/VaultCipher.swift",
                previousPath: nil,
                status: .modified,
                additions: 14,
                deletions: 4,
                baseBlobOID: GitObjectID(rawValue: String(repeating: "2", count: 40)),
                headBlobOID: GitObjectID(rawValue: String(repeating: "3", count: 40)),
                availability: .complete,
                hunks: [DiffHunk(
                    id: DiffHunk.ID(rawValue: "vault-rotation"),
                    header: "@@ -39,6 +39,9 @@ func rotateVaultKey() async throws",
                    oldStart: 39,
                    oldCount: 6,
                    newStart: 39,
                    newCount: 9,
                    lines: [
                        line("1", .context, 39, 39, "let encrypted = try vault.read()"),
                        line("2", .deletion, 40, nil, "try vault.removeOldKey()"),
                        line(
                            "3",
                            .addition,
                            nil,
                            40,
                            "let replacement = try await rotate(encrypted)",
                        ),
                        line("4", .addition, nil, 41, "try vault.store(replacement)"),
                        line("5", .addition, nil, 42, "try vault.removeOldKey()"),
                        line("6", .context, 41, 43, "return replacement"),
                    ],
                )],
            )
        }

        private static var hiddenFile: DiffFile {
            DiffFile(
                path: "Patchlight/PatchlightUI/Sources/Resources/GeneratedStrings.swift",
                previousPath: nil,
                status: .modified,
                additions: 1,
                deletions: 1,
                baseBlobOID: GitObjectID(rawValue: String(repeating: "4", count: 40)),
                headBlobOID: GitObjectID(rawValue: String(repeating: "5", count: 40)),
                availability: .complete,
                hunks: [DiffHunk(
                    id: DiffHunk.ID(rawValue: "generated-strings"),
                    header: "@@ -1,2 +1,2 @@ generated",
                    oldStart: 1,
                    oldCount: 2,
                    newStart: 1,
                    newCount: 2,
                    lines: [
                        line("7", .deletion, 1, nil, "// Generated at 12:02"),
                        line("8", .addition, nil, 1, "// Generated at 12:03"),
                        line("9", .context, 2, 2, "enum Strings {}"),
                    ],
                )],
            )
        }

        private static var snapshotFile: DiffFile {
            DiffFile(
                path: "Patchlight/PatchlightUI/Tests/Snapshots/Dashboard.png",
                previousPath: nil,
                status: .modified,
                additions: 0,
                deletions: 0,
                baseBlobOID: snapshotBaseOID,
                headBlobOID: snapshotHeadOID,
                availability: .binary,
                hunks: [],
            )
        }

        private static func line(
            _ id: String,
            _ kind: DiffLineKind,
            _ oldLine: Int?,
            _ newLine: Int?,
            _ text: String,
        ) -> DiffLine {
            DiffLine(
                id: DiffLine.ID(rawValue: id),
                kind: kind,
                oldLine: oldLine,
                newLine: newLine,
                text: text,
            )
        }

        private static func hunkPlan(
            _ hunk: DiffHunk,
            depth: ReviewDepth,
            category: ReviewCategory,
            partial: Bool,
        ) -> HunkReviewPlan {
            HunkReviewPlan(
                hunk: hunk,
                assessment: ReviewAssessment(
                    hunkID: hunk.id,
                    category: category,
                    minimumDepth: depth,
                    confidence: 1,
                    evidence: ["Visual acceptance fixture"],
                    isPartial: partial,
                ),
                isHardSafetySignal: depth == .critical,
                hasIndependentMechanicalEvidence: depth == .everything,
                aiAnalysis: nil,
            )
        }

        private static func anchor(line: Int) -> DiffAnchor {
            DiffAnchor(
                path: riskFile.path,
                side: .head,
                commitOID: headOID,
                blobOID: riskFile.headBlobOID,
                line: line,
                startLine: nil,
                contextFingerprint: "vault-context",
            )
        }

        private static func rectangle(
            x: Double,
            y: Double,
            width: Double,
            height: Double,
        ) -> NormalizedRectangle {
            do {
                return try NormalizedRectangle(x: x, y: y, width: width, height: height)
            } catch {
                preconditionFailure("A visual fixture rectangle must be valid: \(error)")
            }
        }

        private static func marker(_ annotation: SnapshotAnnotationV1) -> String {
            do {
                return try annotation.marker()
            } catch {
                preconditionFailure("A visual fixture annotation must encode: \(error)")
            }
        }

        private static func uuid(_ value: String) -> UUID {
            guard let value = UUID(uuidString: value) else {
                preconditionFailure("A visual fixture UUID must be valid")
            }
            return value
        }

        private enum ImageVariant {
            case base
            case head
            case heatmap
        }

        private static func png(size: CGSize, variant: ImageVariant) -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                let context = renderer.cgContext
                UIColor.systemBackground
                    .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                    .setFill()
                context.fill(CGRect(origin: .zero, size: size))
                switch variant {
                    case .base:
                        UIColor.systemIndigo.setFill()
                        context.fill(CGRect(x: 36, y: 42, width: size.width - 72, height: 74))
                        UIColor.systemGray5.setFill()
                        context.fill(CGRect(x: 36, y: 148, width: size.width - 72, height: 220))
                        UIColor.systemBlue.setFill()
                        context.fill(CGRect(x: 72, y: 190, width: 210, height: 42))
                    case .head:
                        UIColor.systemIndigo.setFill()
                        context.fill(CGRect(x: 36, y: 42, width: size.width - 72, height: 74))
                        UIColor.systemGray5.setFill()
                        context.fill(CGRect(x: 36, y: 148, width: size.width - 72, height: 220))
                        UIColor.systemBlue.setFill()
                        context.fill(CGRect(x: 72, y: 190, width: 250, height: 42))
                        UIColor.systemOrange.setFill()
                        context.fill(CGRect(x: size.width * 0.58, y: 68, width: 160, height: 92))
                    case .heatmap:
                        UIColor.black.setFill()
                        context.fill(CGRect(origin: .zero, size: size))
                        UIColor.magenta.setFill()
                        context.fill(CGRect(x: size.width * 0.58, y: 68, width: 160, height: 92))
                }
            }
            guard let data = image.pngData() else {
                preconditionFailure("A visual fixture image must encode as PNG")
            }
            return data
        }
    }
#endif
