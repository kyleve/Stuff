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

    @Test func pruneDropsVanishedReposOnlyUnderTheScanDirectory() {
        let scanDirectory = URL(fileURLWithPath: "/Users/dev/Code")
        let kept = RepoID(rawValue: "/Users/dev/Code/Alive")
        let vanished = RepoID(rawValue: "/Users/dev/Code/Deleted")
        // Same string prefix as the scan directory but a sibling path — must
        // survive the prune.
        let sibling = RepoID(rawValue: "/Users/dev/CodeArchive/Old")
        // A different scan directory's history — must survive too.
        let elsewhere = RepoID(rawValue: "/Users/dev/Other/Repo")
        var options = WorkerOptions.standard
        options.verbose = true
        var configuration = ForemanConfiguration(
            scanDirectory: scanDirectory,
            agentExecutable: nil,
            enabledRepoIDs: [kept, vanished, sibling, elsewhere],
            repoOptions: [kept: options, vanished: options, sibling: options],
        )

        let changed = configuration.prune(discovered: [kept], under: scanDirectory)

        #expect(changed)
        #expect(configuration.enabledRepoIDs == [kept, sibling, elsewhere])
        #expect(configuration.repoOptions == [kept: options, sibling: options])
    }

    @Test func pruneWithNothingStaleReportsNoChange() {
        let scanDirectory = URL(fileURLWithPath: "/Users/dev/Code")
        let repo = RepoID(rawValue: "/Users/dev/Code/Alive")
        var configuration = ForemanConfiguration(
            scanDirectory: scanDirectory,
            agentExecutable: nil,
            enabledRepoIDs: [repo],
            repoOptions: [:],
        )
        let before = configuration

        let changed = configuration.prune(discovered: [repo], under: scanDirectory)

        #expect(!changed)
        #expect(configuration == before)
    }
}
