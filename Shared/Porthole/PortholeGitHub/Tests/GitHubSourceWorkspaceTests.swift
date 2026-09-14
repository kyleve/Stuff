import Foundation
import PortholeGitHub
import Testing

struct GitHubSourceWorkspaceTests {
    @Test func dirtyInstalledSourceDoesNotEnterRepositoryPatch() throws {
        var workspace = try GitHubTestFixtures.workspace(isDirty: true)
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        #expect(workspace.patch.isEmpty)
        #expect(workspace.file(at: path)?.text == "let value = 1\n")
        try workspace.setText("let value = 2\n", at: path, mode: .regular)
        #expect(workspace.patch.first?.before?.text == "let value = 1\n")
        #expect(workspace.installedSource.files.first?.text == "let value = 99\n")
        try workspace.setText("let value = 1\n", at: path, mode: .regular)
        #expect(workspace.patch.isEmpty)
    }

    @Test func rejectsUnloadedExistingFileEdits() throws {
        let path = try GitHubRepositoryPath("Sources/Unloaded.swift")
        let snapshot = try GitHubRepositorySnapshot(
            repository: GitHubTestFixtures.repository,
            branch: "main",
            commit: GitHubTestFixtures.commit,
            tree: GitHubTestFixtures.tree,
            knownPaths: [path],
            files: [],
        )
        var workspace = GitHubSourceWorkspace(
            installedSource: GitHubInstalledSource(buildIdentity: "x", isDirty: false, files: []),
            repositoryBase: snapshot,
        )
        #expect(throws: GitHubError.missingBaseFile) { try workspace.setText(
            "replacement",
            at: path,
            mode: .regular,
        ) }
    }

    @Test func addingThenRemovingFileClearsChange() throws {
        var workspace = try GitHubTestFixtures.workspace()
        let path = try GitHubRepositoryPath("new.swift")
        try workspace.setText("new", at: path, mode: .regular)
        try workspace.remove(at: path)
        #expect(workspace.patch.isEmpty)
    }

    @Test(arguments: ["../escape", "/absolute", "a//b", "a/.git/config", "a/../b", "a\nb", "a\\b"])
    func rejectsUnsafePaths(_ path: String) {
        #expect(throws: GitHubError.invalidPath) { try GitHubRepositoryPath(path) }
    }
}
