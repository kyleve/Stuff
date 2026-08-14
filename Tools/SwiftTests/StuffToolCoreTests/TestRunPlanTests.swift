import Foundation
import StuffToolCore
import Testing

struct TestRunPlanTests {
    private var graph: RepositoryGraph {
        get throws {
            try RepositoryGraph(
                tuistGraphData: Data(testPlanTuistFixture.utf8),
                packageDumpData: Data(testPlanPackageFixture.utf8),
                repository: URL(filePath: "/repo", directoryHint: .isDirectory),
            )
        }
    }

    @Test func partitionsBundlesAndOnlyIdentifiersByScheme() throws {
        let plan = try TestRunPlan(
            scope: .bundles,
            bundles: ["CoreTests", "UISnapshotTests"],
            only: ["CoreTests/Suite", "UISnapshotTests/OtherSuite"],
            graph: graph,
        )

        #expect(plan.schemes == [
            TestSchemePlan(
                name: "Stuff-iOS-Tests",
                filters: ["-only-testing:CoreTests", "-only-testing:CoreTests/Suite"],
            ),
            TestSchemePlan(
                name: "StuffSnapshotTests",
                filters: [
                    "-only-testing:UISnapshotTests",
                    "-only-testing:UISnapshotTests/OtherSuite",
                ],
            ),
        ])
        #expect(plan.runsUnitTests)
    }

    @Test func snapshotScopeRunsTheWholeSnapshotScheme() throws {
        let plan = try TestRunPlan(
            scope: .snapshots,
            bundles: [],
            only: [],
            graph: graph,
        )

        #expect(plan.schemes == [
            TestSchemePlan(
                name: "StuffSnapshotTests",
                filters: [],
            ),
        ])
        #expect(plan.runsUnitTests == false)
    }

    @Test func unknownExplicitBundleFailsBeforeXcodebuild() throws {
        #expect(throws: TestRunPlanFailure.unknownBundle("MissingTests")) {
            _ = try TestRunPlan(
                scope: .bundles,
                bundles: ["MissingTests"],
                only: [],
                graph: graph,
            )
        }
    }

    @Test func unitCapabilityFollowsBundleAndIdentifierSelection() throws {
        let snapshotBundle = try TestRunPlan(
            scope: .bundles,
            bundles: ["UISnapshotTests"],
            only: [],
            graph: graph,
        )
        #expect(snapshotBundle.runsUnitTests == false)

        let snapshotIdentifier = try TestRunPlan(
            scope: .only,
            bundles: [],
            only: ["UISnapshotTests/Suite"],
            graph: graph,
        )
        #expect(snapshotIdentifier.runsUnitTests == false)

        let unitIdentifier = try TestRunPlan(
            scope: .only,
            bundles: [],
            only: ["CoreTests/Suite"],
            graph: graph,
        )
        #expect(unitIdentifier.runsUnitTests)
    }
}

private let testPlanTuistFixture = """
{
  "projects":["/repo",{
    "schemes":[
      {"name":"Stuff-iOS-Tests","testAction":{"targets":[{"target":{"name":"CoreTests"}}]}},
      {"name":"StuffSnapshotTests","testAction":{"targets":[{"target":{"name":"UISnapshotTests"}}]}}
    ],
    "targets":{
      "CoreTests":{"dependencies":[{"package":{"product":"Core"}}],"sources":[{"path":"/repo/Core/Tests/CoreTests.swift"}]},
      "UISnapshotTests":{"dependencies":[{"package":{"product":"UI"}}],"sources":[{"path":"/repo/UI/SnapshotTests/UISnapshotTests.swift"}]}
    }
  }]
}
"""

private let testPlanPackageFixture = """
{
  "products":[{"name":"Core","targets":["Core"]},{"name":"UI","targets":["UI"]}],
  "targets":[
    {"name":"Core","path":"Core/Sources","dependencies":[]},
    {"name":"UI","path":"UI/Sources","dependencies":[]}
  ]
}
"""
