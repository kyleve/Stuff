import Foundation
@testable import TestImpactTool
import Testing

struct TestImpactToolTests {
    @Test func sourceInventoryFindsSnapshotSuites() throws {
        let repo = repositoryRoot()
        let inventory = try ProjectInventory(repo: repo)

        #expect(inventory.bundles.count >= 15)
        #expect(inventory.bundles.contains { $0.name == "LedgerCoreTests" } == false)
        #expect(inventory.suites.contains {
            $0.identifier == "BroadwayCatalogTests/BroadwayCatalogTests"
        } == false)
        #expect(inventory.suites.contains {
            $0.identifier == "WhereTests/WhereAppTests"
        })
        #expect(inventory.suites.contains {
            $0.identifier == "WhereUISnapshotTests/CalendarContentViewSnapshotTests"
        })
        #expect(inventory.freeTestBundles.contains("StuffCoreTests"))
    }

    @Test func directTestChangeSelectsItsSuite() throws {
        let engine = try TestImpactEngine(repo: repositoryRoot())

        let selection = try engine.select(
            changedFiles: ["Where/WhereUI/SnapshotTests/CalendarContentViewSnapshotTests.swift"],
            base: "base",
            index: nil,
        )

        #expect(selection.fallback == false)
        #expect(selection.schemes["StuffSnapshotTests"]?.identifiers == [
            "WhereUISnapshotTests/CalendarContentViewSnapshotTests",
        ])
    }

    @Test func snapshotReferenceSelectsItsOwningSuite() throws {
        let engine = try TestImpactEngine(repo: repositoryRoot())

        let selection = try engine.select(
            changedFiles: [
                "Where/WhereUI/SnapshotTests/__Snapshots__/CalendarContentViewSnapshotTests/calendar.png",
            ],
            base: "base",
            index: nil,
        )

        #expect(selection.fallback == false)
        #expect(selection.schemes["StuffSnapshotTests"]?.identifiers == [
            "WhereUISnapshotTests/CalendarContentViewSnapshotTests",
        ])
    }

    @Test func missingIndexFallsBackToAllSuites() throws {
        let engine = try TestImpactEngine(repo: repositoryRoot())

        let selection = try engine.select(
            changedFiles: ["Where/WhereUI/Sources/CalendarContentView.swift"],
            base: "base",
            index: nil,
        )

        #expect(selection.fallback)
        #expect(selection.schemes["Stuff-iOS-Tests"]?.scope == "all")
        #expect(selection.schemes["StuffSnapshotTests"]?.scope == "all")
    }

    @Test func directTestDoesNotMaskUnresolvedProductionChange() throws {
        let engine = try TestImpactEngine(repo: repositoryRoot())
        let emptyIndex = SemanticIndex(files: [:], referencingFiles: [:])

        let selection = try engine.select(
            changedFiles: [
                "Where/WhereUI/Sources/CalendarContentView.swift",
                "Where/WhereUI/SnapshotTests/CalendarContentViewSnapshotTests.swift",
            ],
            base: "base",
            index: emptyIndex,
        )

        #expect(selection.fallback)
        #expect(selection.schemes["Stuff-iOS-Tests"]?.scope == "all")
        #expect(selection.schemes["StuffSnapshotTests"]?.scope == "all")
    }

    @Test func globalInvalidatorFallsBackToAllSuites() throws {
        let engine = try TestImpactEngine(repo: repositoryRoot())

        let selection = try engine.select(
            changedFiles: ["Package.swift"],
            base: "base",
            index: nil,
        )

        #expect(selection.fallback)
        #expect(selection.reasons.contains { $0.reason == "global invalidator" })
    }

    @Test func emptyDiffFallsBackForMainBranchShadowRuns() throws {
        let engine = try TestImpactEngine(repo: repositoryRoot())

        let selection = try engine.select(changedFiles: [], base: "base", index: nil)

        #expect(selection.fallback)
        #expect(selection.schemes["Stuff-iOS-Tests"]?.scope == "all")
        #expect(selection.schemes["StuffSnapshotTests"]?.scope == "all")
        #expect(selection.reasons.contains { $0.reason == "no-diff full-suite fallback" })
    }

    @Test func compilerIndexReachesAnIndirectTestSuite() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "test-impact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let sourceRoot = temporary.appending(path: "Example/Tests")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let production = temporary.appending(path: "Production.swift")
        let tests = sourceRoot.appending(path: "ExampleTests.swift")
        try Data("struct Value {}\nfunc consume(_: Value) {}\n".utf8).write(to: production)
        try Data("""
        struct ExampleTests {
            func consumesValue() { consume(Value()) }
        }
        """.utf8).write(to: tests)
        let declarations = (0 ..< 15).map { index in
            let name = index == 0 ? "ExampleTests" : "Placeholder\(index)Tests"
            let source = index == 0 ? "Example/Tests/**" : "Missing/\(index)/**"
            return """
                    unitTests(
                        name: "\(name)",
                        sources: ["\(source)"],
                    ),
            """
        }.joined(separator: "\n")
        try Data(declarations.utf8).write(to: temporary.appending(path: "Project.swift"))
        let store = temporary.appending(path: "IndexStore")
        let sdk = try CommandRunner().output(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
        let compilerPrefix = [
            "xcrun",
            "swift-frontend",
            "-typecheck",
            "-parse-as-library",
            "-sdk",
            sdk,
            "-index-store-path",
            store.path,
        ]
        _ = try CommandRunner().output(
            compilerPrefix + [
                "-index-unit-output-path",
                temporary.appending(path: "Production.o").path,
                "-primary-file",
                production.path,
                tests.path,
            ],
            directory: temporary,
        )
        _ = try CommandRunner().output(
            compilerPrefix + [
                "-index-unit-output-path",
                temporary.appending(path: "Tests.o").path,
                production.path,
                "-primary-file",
                tests.path,
            ],
            directory: temporary,
        )
        let developer = try CommandRunner().output(["xcode-select", "-p"])
        let library = URL(fileURLWithPath: developer)
            .appending(path: "Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib")
        let index = try await SemanticIndex.load(
            storePath: store,
            libraryPath: library,
            repo: temporary,
        )
        let inventory = try ProjectInventory(repo: temporary)

        let reached = index.reachableTestFiles(
            from: ["Production.swift"],
            inventory: inventory,
        )

        #expect(reached == ["Example/Tests/ExampleTests.swift"])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
