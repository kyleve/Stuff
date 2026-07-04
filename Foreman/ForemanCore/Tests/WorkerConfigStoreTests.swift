import ForemanCore
import Foundation
import Testing

struct WorkerConfigStoreTests {
    @Test func loadWithoutAFileIsTheFirstLaunchConfiguration() throws {
        let store = try WorkerConfigStore(directory: makeTemporaryDirectory())

        #expect(try store.load() == .initial)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = try WorkerConfigStore(directory: makeTemporaryDirectory())
        let repo = RepoID(rawValue: "/Users/dev/Development/Thing")
        var options = WorkerOptions.standard
        options.assignment = .pool(name: "builds")
        let configuration = ForemanConfiguration(
            scanDirectory: URL(fileURLWithPath: "/Users/dev/Code"),
            agentExecutable: URL(fileURLWithPath: "/usr/local/bin/cursor-agent"),
            enabledRepoIDs: [repo],
            repoOptions: [repo: options],
        )

        try store.save(configuration)

        #expect(try store.load() == configuration)
    }

    @Test func savingCreatesTheStoreDirectory() throws {
        let base = try makeTemporaryDirectory()
        let store = WorkerConfigStore(directory: base.appendingPathComponent("nested/config"))

        try store.save(.initial)

        #expect(try store.load() == .initial)
    }

    @Test func corruptFileThrowsInsteadOfSilentlyResetting() throws {
        let directory = try makeTemporaryDirectory()
        let store = WorkerConfigStore(directory: directory)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("configuration.json"))

        #expect(throws: (any Error).self) {
            try store.load()
        }
    }

    @Test func optionsForAnUncustomizedRepoAreStandard() {
        let configuration = ForemanConfiguration.initial

        #expect(configuration.options(for: RepoID(rawValue: "/nowhere")) == .standard)
    }

    @Test func scanDirectoryDefaultsToDevelopment() {
        let configuration = ForemanConfiguration.initial

        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Development")
        #expect(configuration.resolvedScanDirectory == expected)
    }
}
