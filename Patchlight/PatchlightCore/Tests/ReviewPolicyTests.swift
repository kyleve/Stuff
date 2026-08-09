import Foundation
import PatchlightCore
import Testing

struct ReviewPolicyTests {
    @Test func reviewDepthsAreMonotonicAndKeepBalancedAsTheMiddleDefault() {
        #expect(ReviewDepth.allCases == [
            .critical,
            .focused,
            .balanced,
            .thorough,
            .everything,
        ])
        #expect(ReviewDepth.critical < .focused)
        #expect(ReviewDepth.focused < .balanced)
        #expect(ReviewDepth.balanced < .thorough)
        #expect(ReviewDepth.thorough < .everything)
    }

    @Test func globSupportsSegmentRecursiveAndSingleCharacterWildcards() throws {
        #expect(try PatchlightPathGlob("Sources/*.swift").matches("Sources/App.swift"))
        #expect(try !(PatchlightPathGlob("Sources/*.swift").matches("Sources/UI/App.swift")))
        #expect(try PatchlightPathGlob("**/Snapshots/**/*.png")
            .matches("Foo/Tests/Snapshots/Dark/Card.png"))
        #expect(try PatchlightPathGlob("Tests/?.png").matches("Tests/a.png"))
        #expect(try !(PatchlightPathGlob("Tests/?.png").matches("Tests/ab.png")))
        #expect(try PatchlightPathGlob(".\\Tests\\*.swift").matches("Tests/AppTests.swift"))
    }

    @Test func unknownConfigurationVersionFallsBackWithTypedWarning() {
        let data = Data("{\"version\":2,\"review\":{},\"snapshots\":{}}".utf8)
        #expect(throws: PatchlightConfigurationError.unsupportedVersion(2)) {
            try PatchlightRepositoryConfigurationV1.decode(data)
        }
    }

    @Test func invalidPatternMakesTheWholeConfigurationInvalid() {
        let data = Data("""
        {"version":1,"review":{"alwaysReview":[""],"generated":[],"mechanical":[],"tests":[]},
        "snapshots":{"include":[],"exclude":[]}}
        """.utf8)
        #expect(throws: PatchlightConfigurationError.invalidPattern("")) {
            try PatchlightRepositoryConfigurationV1.decode(data)
        }
    }

    @Test func hardSignalsAndAlwaysReviewDominateMechanicalHints() {
        let configuration = configuration(
            alwaysReview: ["Sources/Auth.swift"],
            generated: ["Sources/Auth.swift"],
        )
        let workspace = workspace(
            files: [file(path: "Sources/Auth.swift", additions: 1, deletions: 1)],
            configuration: .loaded(configuration),
        )

        let plan = analyze(workspace)

        #expect(plan.files.first?.minimumDepth == .critical)
        #expect(plan.files.first?.hunks.first?.assessment.minimumDepth == .critical)
    }

    @Test func changedConfigurationIsCriticalAndCannotGovernItsOwnReview() {
        let configuration = configuration(
            alwaysReview: [],
            generated: [".patchlight.json"],
        )
        let workspace = workspace(
            files: [file(path: ".patchlight.json", additions: 1, deletions: 1)],
            configuration: .loaded(configuration),
        )

        #expect(analyze(workspace).files.first?.minimumDepth == .critical)
    }

    @Test func sizeSensitiveAndExactMechanicalGatesStayMonotonic() {
        let files = [
            file(path: "Sources/Huge.swift", additions: 500, deletions: 0),
            file(path: "Sources/Medium.swift", additions: 200, deletions: 0),
            file(path: "Config/App.entitlements", additions: 1, deletions: 0),
            whitespaceOnlyFile(),
        ]

        let plan = analyze(workspace(files: files, configuration: .absent))
        let depths = Dictionary(uniqueKeysWithValues: plan.files.map { (
            $0.file.path,
            $0.minimumDepth,
        ) })

        #expect(depths["Sources/Huge.swift"] == .focused)
        #expect(depths["Sources/Medium.swift"] == .balanced)
        #expect(depths["Config/App.entitlements"] == .focused)
        #expect(depths["Sources/Whitespace.swift"] == .everything)
    }

    @Test func snapshotsRouteByConventionConfigAndManualOverride() {
        let files = [
            file(path: "Feature/Tests/Snapshots/Card.png", additions: 0, deletions: 0),
            file(path: "Visual/Golden/Card.png", additions: 0, deletions: 0),
            file(path: "Assets/Manual.png", additions: 0, deletions: 0),
        ]
        let configuration = PatchlightRepositoryConfigurationV1(
            review: configuration(alwaysReview: [], generated: []).review,
            snapshots: PatchlightSnapshotRules(
                include: ["Visual/Golden/*.png"],
                exclude: [],
            ),
        )
        let workspace = workspace(files: files, configuration: .loaded(configuration))

        let plan = DeterministicReviewAnalyzer.analyze(
            workspace: workspace,
            localRules: nil,
            localSnapshotRules: nil,
            manualSnapshotPaths: ["Assets/Manual.png"],
            threadPaths: [],
            draftPaths: [],
            corrections: [],
        )

        #expect(Set(plan.files.filter(\.isSnapshot).map(\.file.path)) == [
            "Feature/Tests/Snapshots/Card.png",
            "Visual/Golden/Card.png",
            "Assets/Manual.png",
        ])
    }

    @Test func localRulesTakePrecedenceOverBaseRules() {
        let base = configuration(alwaysReview: [], generated: ["Sources/App.swift"])
        let local = PatchlightReviewRules(
            alwaysReview: [],
            generated: [],
            mechanical: [],
            tests: [],
        )
        let workspace = workspace(
            files: [file(path: "Sources/App.swift", additions: 1, deletions: 0)],
            configuration: .loaded(base),
        )

        let plan = DeterministicReviewAnalyzer.analyze(
            workspace: workspace,
            localRules: local,
            localSnapshotRules: nil,
            manualSnapshotPaths: [],
            threadPaths: [],
            draftPaths: [],
            corrections: [],
        )

        #expect(plan.files.first?.minimumDepth == .balanced)
    }

    private func analyze(_ workspace: PullRequestWorkspace) -> DeterministicReviewPlan {
        DeterministicReviewAnalyzer.analyze(
            workspace: workspace,
            localRules: nil,
            localSnapshotRules: nil,
            manualSnapshotPaths: [],
            threadPaths: [],
            draftPaths: [],
            corrections: [],
        )
    }

    private func configuration(
        alwaysReview: [String],
        generated: [String],
    ) -> PatchlightRepositoryConfigurationV1 {
        PatchlightRepositoryConfigurationV1(
            review: PatchlightReviewRules(
                alwaysReview: alwaysReview,
                generated: generated,
                mechanical: [],
                tests: ["**/Tests/**"],
            ),
            snapshots: PatchlightSnapshotRules(include: [], exclude: []),
        )
    }

    private func workspace(
        files: [DiffFile],
        configuration: RepositoryConfigurationState,
    ) -> PullRequestWorkspace {
        PullRequestWorkspace(
            summary: PullRequestSummary(
                id: PatchlightCoreTestSupport.pullRequestID,
                repository: RepositoryCoordinates(owner: "acme", name: "widget"),
                title: "Review",
                authorLogin: "author",
                isDraft: false,
                headOID: PatchlightCoreTestSupport.objectID(),
                createdAt: .distantPast,
                updatedAt: Date(),
                reviewRequestSource: .direct,
                actionability: .directRequest,
            ),
            bodyMarkdown: nil,
            baseOID: PatchlightCoreTestSupport.objectID("b"),
            files: files,
            isFileListComplete: true,
            repositoryConfiguration: configuration,
        )
    }

    private func file(path: String, additions: Int, deletions: Int) -> DiffFile {
        let lines = [DiffLine(
            id: .init(rawValue: "\(path)-line"),
            kind: additions > 0 ? .addition : .context,
            oldLine: nil,
            newLine: 1,
            text: "changed behavior",
        )]
        return DiffFile(
            path: path,
            previousPath: nil,
            status: .modified,
            additions: additions,
            deletions: deletions,
            baseBlobOID: nil,
            headBlobOID: nil,
            availability: .complete,
            hunks: [DiffHunk(
                id: .init(rawValue: "\(path)-hunk"),
                header: "@@",
                oldStart: 1,
                oldCount: deletions,
                newStart: 1,
                newCount: additions,
                lines: lines,
            )],
        )
    }

    private func whitespaceOnlyFile() -> DiffFile {
        let lines = [
            DiffLine(
                id: .init(rawValue: "old"),
                kind: .deletion,
                oldLine: 1,
                newLine: nil,
                text: "let x=1",
            ),
            DiffLine(
                id: .init(rawValue: "new"),
                kind: .addition,
                oldLine: nil,
                newLine: 1,
                text: "let x = 1",
            ),
        ]
        return DiffFile(
            path: "Sources/Whitespace.swift",
            previousPath: nil,
            status: .modified,
            additions: 1,
            deletions: 1,
            baseBlobOID: nil,
            headBlobOID: nil,
            availability: .complete,
            hunks: [DiffHunk(
                id: .init(rawValue: "whitespace"),
                header: "@@",
                oldStart: 1,
                oldCount: 1,
                newStart: 1,
                newCount: 1,
                lines: lines,
            )],
        )
    }
}
