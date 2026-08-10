import Foundation
import StuffToolCore
import Testing

struct RepositoryGraphTests {
    @Test func affectedClosureUsesTuistSourcesSchemesHostsAndPackageDependencies() throws {
        let graph = try RepositoryGraph(
            tuistGraphData: fixtureData("tuist-graph", extension: "json"),
            packageDumpData: fixtureData("package-dump", extension: "json"),
            repository: URL(filePath: "/repo", directoryHint: .isDirectory),
        )

        #expect(graph.unitBundles == ["CatalogTests", "CoreTests"])
        #expect(graph.snapshotBundles == ["UISnapshotTests"])
        #expect(graph.affectedBundles(changedPaths: ["Core/Sources/Core.swift"]) == [
            "CatalogTests",
            "CoreTests",
            "UISnapshotTests",
        ])
        #expect(graph.affectedBundles(changedPaths: ["UI/Sources/UI.swift"]) == [
            "CatalogTests",
            "UISnapshotTests",
        ])
        #expect(graph.affectedBundles(changedPaths: ["Core/Tests/CoreTests.swift"]) == [
            "CoreTests",
        ])
        #expect(graph.affectedBundles(changedPaths: ["App/Sources/App.swift"]) == [
            "CatalogTests",
        ])
        #expect(graph.affectedBundles(changedPaths: ["Project.swift"]) == [
            "CatalogTests",
            "CoreTests",
            "UISnapshotTests",
        ])
        #expect(graph.affectedBundles(changedPaths: ["Tools/SwiftTests/NewTest.swift"]) == [
            "CatalogTests",
            "CoreTests",
            "UISnapshotTests",
        ])
        #expect(graph.affectedBundles(changedPaths: ["README.md"]).isEmpty)
    }

    @Test func missingRequiredSchemeFailsClosed() throws {
        let fixture = try String(
            decoding: fixtureData("tuist-graph", extension: "json"),
            as: UTF8.self,
        )
        let incomplete = fixture.replacingOccurrences(
            of: "StuffSnapshotTests",
            with: "OtherSnapshots",
        )

        #expect(throws: RepositoryGraphFailure.missingScheme("StuffSnapshotTests")) {
            _ = try RepositoryGraph(
                tuistGraphData: Data(incomplete.utf8),
                packageDumpData: fixtureData("package-dump", extension: "json"),
                repository: URL(filePath: "/repo", directoryHint: .isDirectory),
            )
        }
    }
}
