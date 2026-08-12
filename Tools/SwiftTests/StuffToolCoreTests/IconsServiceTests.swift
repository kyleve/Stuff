import Foundation
import StuffToolCore
import Testing

struct IconsServiceTests {
    @Test func addAndRemoveCommitAllThreeCatalogSurfaces() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let fileSystem = FoundationFileSystem()
        try makeIconRepository(root, fileSystem: fileSystem)
        let image = try writeIconFixture(root, fileSystem: fileSystem)
        let terminal = MemoryTerminal()
        let service = IconsService(
            fileSystem: fileSystem,
            terminal: terminal,
            repository: root,
            transactionIdentifier: { "success" },
        )

        try await service.run(
            .add(
                IconAddRequest(
                    lightPath: "art/ocean.png",
                    name: "Ocean",
                    id: nil,
                    darkPath: "art/ocean.png",
                    tintedPath: "art/ocean.png",
                    dryRun: false,
                ),
            ),
        )

        let appSet = root.appending(
            path: "Where/Where/Resources/AppIcon.xcassets/AppIconOcean.appiconset",
            directoryHint: .isDirectory,
        )
        let previewSet = root.appending(
            path: "Where/WhereUI/Sources/Resources/AppIconPreviews.xcassets/" +
                "AppIconOcean.imageset",
            directoryHint: .isDirectory,
        )
        #expect(try fileSystem.read(appSet.appending(path: "AppIconOcean.png")) == image)
        #expect(try fileSystem.read(appSet.appending(path: "AppIconOcean-Dark.png")) == image)
        #expect(try fileSystem.read(appSet.appending(path: "AppIconOcean-Tinted.png")) == image)
        #expect(try fileSystem.read(previewSet.appending(path: "AppIconOcean.png")) == image)
        #expect(try fileSystem
            .kind(of: previewSet.appending(path: "AppIconOcean-Tinted.png")) == .missing)
        let manifestURL = iconManifestURL(root)
        let added = try IconCatalogPlanner().decodeManifest(
            fileSystem.read(manifestURL),
            pathDescription: "AppIcons.json",
        )
        #expect(added.icons.map(\.id) == ["classic", "pride", "ocean"])
        #expect(try fileSystem
            .kind(of: root.appending(path: ".stuff-icons-transaction-success")) == .missing)

        try await service.run(.remove(IconRemoveRequest(target: "OCEAN", dryRun: false)))

        #expect(try fileSystem.kind(of: appSet) == .missing)
        #expect(try fileSystem.kind(of: previewSet) == .missing)
        #expect(try fileSystem.read(manifestURL) == fixtureData("app-icons", extension: "json"))
        #expect(await terminal.standardOutputText.contains("Added \"Ocean\""))
        #expect(await terminal.standardOutputText.contains("Removed \"Ocean\""))
    }

    @Test func dryRunFullyValidatesWithoutCreatingStagingOrTargets() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let fileSystem = FoundationFileSystem()
        try makeIconRepository(root, fileSystem: fileSystem)
        _ = try writeIconFixture(root, fileSystem: fileSystem)
        let original = try fileSystem.read(iconManifestURL(root))
        let terminal = MemoryTerminal()
        let service = IconsService(
            fileSystem: fileSystem,
            terminal: terminal,
            repository: root,
            transactionIdentifier: { "dry" },
        )

        try await service.run(
            .add(
                IconAddRequest(
                    lightPath: "art/ocean.png",
                    name: "Ocean",
                    id: nil,
                    darkPath: nil,
                    tintedPath: nil,
                    dryRun: true,
                ),
            ),
        )

        #expect(try fileSystem.read(iconManifestURL(root)) == original)
        #expect(try fileSystem.kind(of: root.appending(
            path: "Where/Where/Resources/AppIcon.xcassets/AppIconOcean.appiconset",
        )) == .missing)
        #expect(try fileSystem
            .kind(of: root.appending(path: ".stuff-icons-transaction-dry")) == .missing)
        #expect(await terminal.standardOutputText.contains("no files changed"))
    }

    @Test func injectedMidCommitFailureRestoresTheOriginalTree() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let base = FoundationFileSystem()
        try makeIconRepository(root, fileSystem: base)
        _ = try writeIconFixture(root, fileSystem: base)
        let original = try base.read(iconManifestURL(root))
        let faulting = FaultInjectingFileSystem(base: base, failingMove: 4)
        let service = IconsService(
            fileSystem: faulting,
            terminal: MemoryTerminal(),
            repository: root,
            transactionIdentifier: { "rollback" },
        )

        do {
            try await service.run(
                .add(
                    IconAddRequest(
                        lightPath: "art/ocean.png",
                        name: "Ocean",
                        id: nil,
                        darkPath: nil,
                        tintedPath: nil,
                        dryRun: false,
                    ),
                ),
            )
            Issue.record("expected the injected commit failure")
        } catch is InjectedMoveFailure {
            // Expected.
        }

        #expect(try base.read(iconManifestURL(root)) == original)
        #expect(try base.kind(of: root.appending(
            path: "Where/Where/Resources/AppIcon.xcassets/AppIconOcean.appiconset",
        )) == .missing)
        #expect(try base.kind(of: root.appending(
            path: "Where/WhereUI/Sources/Resources/AppIconPreviews.xcassets/" +
                "AppIconOcean.imageset",
        )) == .missing)
        #expect(try base
            .kind(of: root.appending(path: ".stuff-icons-transaction-rollback")) == .missing)
    }

    @Test func rollbackFailurePreservesTheTransactionForManualRecovery() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let base = FoundationFileSystem()
        try makeIconRepository(root, fileSystem: base)
        _ = try writeIconFixture(root, fileSystem: base)
        let original = try base.read(iconManifestURL(root))
        let transactionRoot = root.appending(
            path: ".stuff-icons-transaction-recovery",
            directoryHint: .isDirectory,
        )
        let faulting = FaultInjectingFileSystem(base: base, failingMoves: [4, 5])
        let service = IconsService(
            fileSystem: faulting,
            terminal: MemoryTerminal(),
            repository: root,
            transactionIdentifier: { "recovery" },
        )

        do {
            try await service.run(
                .add(IconAddRequest(
                    lightPath: "art/ocean.png",
                    name: "Ocean",
                    id: nil,
                    darkPath: nil,
                    tintedPath: nil,
                    dryRun: false,
                )),
            )
            Issue.record("expected rollback failure")
        } catch let failure as FileReplacementTransactionFailure {
            #expect(failure.description.contains(transactionRoot.appending(path: "backup").path))
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(try base.kind(of: transactionRoot) == .directory)
        #expect(
            try base.read(transactionRoot.appending(path: "backup/2")) == original,
        )
    }

    @Test func listPreservesTheLegacyAlignedOutput() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let fileSystem = FoundationFileSystem()
        try makeIconRepository(root, fileSystem: fileSystem)
        let terminal = MemoryTerminal()
        let service = IconsService(
            fileSystem: fileSystem,
            terminal: terminal,
            repository: root,
            transactionIdentifier: { "unused" },
        )

        try await service.run(.list)

        #expect(await terminal.standardOutputText == """
          classic  Classic  (primary)
          pride    Pride    AppIconPride

        """)
    }
}

private func makeIconRepository(_ root: URL, fileSystem: FoundationFileSystem) throws {
    try fileSystem.createDirectory(
        at: root.appending(
            path: "Where/Where/Resources/AppIcon.xcassets",
            directoryHint: .isDirectory,
        ),
        withIntermediateDirectories: true,
    )
    try fileSystem.createDirectory(
        at: root.appending(
            path: "Where/WhereUI/Sources/Resources/AppIconPreviews.xcassets",
            directoryHint: .isDirectory,
        ),
        withIntermediateDirectories: true,
    )
    let manifest = iconManifestURL(root)
    try fileSystem.createDirectory(
        at: manifest.deletingLastPathComponent(),
        withIntermediateDirectories: true,
    )
    try fileSystem.write(
        fixtureData("app-icons", extension: "json"),
        to: manifest,
        atomically: false,
    )
}

private func writeIconFixture(_ root: URL, fileSystem: FoundationFileSystem) throws -> Data {
    let directory = root.appending(path: "art", directoryHint: .isDirectory)
    try fileSystem.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = pngFixtureData()
    try fileSystem.write(data, to: directory.appending(path: "ocean.png"), atomically: false)
    return data
}

private func iconManifestURL(_ root: URL) -> URL {
    root.appending(path: "Where/WhereUI/Sources/Resources/AppIcons.json")
}
