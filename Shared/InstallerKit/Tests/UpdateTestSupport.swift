import Foundation
@_spi(Testing) @testable import InstallerKit

enum UpdateFixtures {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let feedURL = URL(string: "https://updates.example.com/updates.json")!
    static let channel = InstalledBuild.Channel(rawValue: "pr-42")!

    static func revision(_ number: UInt64) -> InstalledBuild.Revision {
        InstalledBuild.Revision(rawValue: String(format: "%040llx", number))!
    }

    static func stamp(run: UInt64 = 1, channel: String = "pr-42") -> [String: String] {
        [
            "InstallerAppID": "where",
            "CFBundleIdentifier": "com.stuff.where.development",
            "InstallerRepositoryURL": "https://github.com/fixture/Stuff",
            "InstallerGitStatus": "clean",
            "InstallerChannel": channel,
            "InstallerRun": String(run),
            "InstallerAttempt": "1",
            "InstallerGitSHA": revision(run).rawValue,
            "InstallerFeedURL": feedURL.absoluteString,
        ]
    }

    static func installed(run: UInt64 = 1, channel: String = "pr-42") -> InstalledBuild {
        InstalledBuild(infoDictionary: stamp(run: run, channel: channel))!
    }

    static func localStamp(status: String = "clean") -> [String: String] {
        var stamp = stamp(channel: "local")
        stamp["InstallerGitStatus"] = status
        stamp["InstallerRun"] = "unknown"
        stamp["InstallerAttempt"] = "unknown"
        return stamp
    }

    static func localInstalled(status: String = "clean") -> InstalledBuild {
        InstalledBuild(infoDictionary: localStamp(status: status))!
    }

    static func release(
        _ run: UInt64,
        historyChanged: Bool = false,
        appID: String = "where",
        channel: String = "pr-42",
        feedURL: URL = UpdateFixtures.feedURL,
        buildDetails: UpdateCatalog.BuildDetails? = nil,
    ) -> UpdateCatalog
        .Release
    {
        .init(
            id: .init(run: run, attempt: 1),
            sha: revision(run),
            publishedAt: date,
            manifestURL: feedURL.deletingLastPathComponent()
                .appending(path: "manifests/\(appID)/\(channel)/\(run)-1.plist"),
            baseSHA: run > 1 ? revision(run - 1) : nil,
            historyChanged: historyChanged,
            commits: [.init(sha: revision(run), subject: "Change \(run)")],
            buildDetails: buildDetails,
        )
    }

    static func withChannels(_ channels: [UpdateCatalog.Channel]) -> UpdateCatalog {
        .init(
            schemaVersion: 3,
            apps: [.init(
                id: InstallerAppID(rawValue: "where")!,
                name: "Where Dev",
                bundleIdentifier: "com.stuff.where.development",
                channels: channels,
            )],
        )
    }

    static func catalog(
        _ runs: [UInt64],
        active: Bool = true,
        feedURL: URL = UpdateFixtures.feedURL,
    ) -> UpdateCatalog {
        .init(
            schemaVersion: 3,
            apps: [.init(
                id: InstallerAppID(rawValue: "where")!,
                name: "Where Dev",
                bundleIdentifier: "com.stuff.where.development",
                channels: [.init(
                    name: channel,
                    active: active,
                    releases: runs.map { release($0, feedURL: feedURL) },
                )],
            )],
        )
    }
}

actor UpdateTestClient: UpdateFetching {
    enum Failure: Error { case offline }
    private(set) var calls = 0
    var result: Result<UpdateCatalog, Failure>

    init(_ result: Result<UpdateCatalog, Failure>) {
        self.result = result
    }

    func setResult(_ value: Result<UpdateCatalog, Failure>) {
        result = value
    }

    func fetch(from _: URL) async throws -> UpdateCatalog {
        calls += 1
        return try result.get()
    }
}

/// Holds each response at the suspension boundary, including cancelled requests.
actor HeldUpdateClient: UpdateFetching {
    struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var requests: [CheckedContinuation<UpdateCatalog, any Error>] = []
    private var waiters: [Waiter] = []

    func fetch(from _: URL) async throws -> UpdateCatalog {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(continuation)
            let ready = waiters.filter { $0.count <= requests.count }
            waiters.removeAll { $0.count <= requests.count }
            ready.forEach { $0.continuation.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiters.append(Waiter(count: count, continuation: $0)) }
    }

    func resume(_ index: Int, catalog: UpdateCatalog) {
        requests[index].resume(returning: catalog)
    }
}

final class MemoryUpdatePreferences: UpdatePreferencesStoring {
    var installerUpdates = UpdatePreferences(cached: nil)
}

extension UpdateFixtures {
    static func browserChannel(_ name: String, runs: [UInt64], active: Bool = true) -> UpdateCatalog
        .Channel
    {
        .init(
            name: InstalledBuild.Channel(rawValue: name)!,
            active: active,
            releases: runs.map { release($0, channel: name) },
        )
    }

    static func selection(channel: String, run: UInt64) -> UpdateBuildBrowser.Selection {
        .init(
            channel: InstalledBuild.Channel(rawValue: channel)!,
            build: .init(run: run, attempt: 1),
        )
    }
}
