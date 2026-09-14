import PortholeGitHub
import Testing

struct GitHubPatchReviewTests {
    @Test func emptyFileAdditionDoesNotInventAnEmptyHunk() throws {
        let path = try GitHubRepositoryPath("empty.txt")
        let after = GitHubSourceFile(path: path, text: "", mode: .regular)
        let diff = try GitHubPatchReview.unifiedDiff(for: [GitHubFileChange(
            path: path,
            before: nil,
            after: after,
        )])
        #expect(diff.contains("new file mode 100644"))
        #expect(diff.contains("@@") == false)
    }

    @Test func preservesTrailingNewlineChangeInReview() throws {
        let path = try GitHubRepositoryPath("example.swift")
        let before = GitHubSourceFile(path: path, text: "same\n", mode: .regular)
        let after = GitHubSourceFile(path: path, text: "same", mode: .regular)
        let diff = try GitHubPatchReview.unifiedDiff(for: [GitHubFileChange(
            path: path,
            before: before,
            after: after,
        )])
        #expect(diff.contains("-same\n+same\n\\ No newline at end of file\n"))
    }

    @Test func includesDeletionAndExecutableMode() throws {
        let path = try GitHubRepositoryPath("run.sh")
        let before = GitHubSourceFile(path: path, text: "run\n", mode: .executable)
        let diff = try GitHubPatchReview.unifiedDiff(for: [GitHubFileChange(
            path: path,
            before: before,
            after: nil,
        )])
        #expect(diff.contains("deleted file mode 100755"))
        #expect(diff.contains("+++ /dev/null"))
        #expect(diff.contains("@@ -1,1 +0,0 @@"))
    }
}
