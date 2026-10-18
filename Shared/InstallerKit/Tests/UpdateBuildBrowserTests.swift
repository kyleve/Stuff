import Foundation
@testable import InstallerKit
import Testing

struct UpdateBuildBrowserTests {
    private typealias F = UpdateFixtures

    @Test func localCanInstallMainAndPRsWithoutMistakingTheSameCommitForAnInstalledRelease() throws {
        let catalog = F.withChannels([
            F.browserChannel("pr-42", runs: [2, 1]),
            F.browserChannel("main", runs: [1]),
            F.browserChannel("pr-3", runs: [3], active: false),
        ])
        try catalog.validate(feedURL: F.feedURL)
        let browser = UpdateBuildBrowser(catalog: catalog, installed: F.localInstalled())
        #expect(browser.channels.map(\.id.rawValue) == ["main", "pr-42"])
        for selection in [
            F.selection(channel: "main", run: 1),
            F.selection(channel: "pr-42", run: 1),
        ] {
            let build = try #require(browser.build(for: selection))
            #expect(!build.isInstalled)
            #expect(build.release.installURL.scheme == "itms-services")
        }
    }

    @Test func listsOnlyThisAppsActiveChannelsWithMainFirstAndRecentPRsNext() throws {
        let catalog = F.withChannels([
            F.browserChannel("pr-1", runs: [4, 3]),
            F.browserChannel("pr-2", runs: [8]),
            F.browserChannel("main", runs: [2]),
            F.browserChannel("pr-3", runs: [9], active: false),
        ])
        let otherApp = try UpdateCatalog.App(
            id: #require(InstallerAppID(rawValue: "other")),
            name: "Other",
            bundleIdentifier: "com.example.other",
            channels: [.init(name: F.channel, active: true, releases: [
                F.release(100, appID: "other"),
            ])],
        )
        let combined = UpdateCatalog(schemaVersion: 3, apps: catalog.apps + [otherApp])
        try combined.validate(feedURL: F.feedURL)
        let browser = UpdateBuildBrowser(catalog: combined, installed: F.installed())
        #expect(browser.channels.map(\.id.rawValue) == ["main", "pr-2", "pr-1"])
        #expect(browser.channels.last?.releases.map(\.id.run) == [4, 3])
    }

    @Test(arguments: ["InstallerAppID", "CFBundleIdentifier"], [false, true])
    func requiresBothInstalledAppIdentities(key: String, isLocal: Bool) throws {
        var stamp = isLocal ? F.localStamp() : F.stamp()
        stamp[key] = key == "InstallerAppID" ? "other" : "com.example.other"
        let browser = try UpdateBuildBrowser(
            catalog: F.catalog([2, 1]),
            installed: #require(InstalledBuild(infoDictionary: stamp)),
        )
        #expect(browser.channels.isEmpty)
    }

    @Test func manualSelectionAllowsOtherChannelsAndOlderReleasesWithoutChangingUpdates() throws {
        let catalog = F.withChannels([
            F.browserChannel("main", runs: [20, 15]),
            F.browserChannel("pr-42", runs: [10, 9]),
        ])
        let installed = F.installed(run: 20, channel: "main")
        let browser = UpdateBuildBrowser(catalog: catalog, installed: installed)
        for selection in [
            F.selection(channel: "pr-42", run: 10),
            F.selection(channel: "pr-42", run: 9),
            F.selection(channel: "main", run: 15),
        ] {
            let build = try #require(browser.build(for: selection))
            #expect(!build.isInstalled)
            #expect(build.release.manifestURL.path.hasSuffix(
                "/\(selection.channel.rawValue)/\(selection.build.run)-1.plist",
            ))
        }
        #expect(catalog.availability(for: installed) == .current)
    }

    @Test func installedMarkerRequiresChannelBuildAttemptAndRevision() throws {
        let catalog = F.withChannels([
            F.browserChannel("main", runs: [2]),
            F.browserChannel("pr-42", runs: [2]),
        ])
        let browser = UpdateBuildBrowser(catalog: catalog, installed: F.installed(run: 2))
        #expect(try #require(browser.build(for: F.selection(channel: "pr-42", run: 2))).isInstalled)
        #expect(try #require(browser.build(for: F.selection(channel: "main", run: 2)))
            .isInstalled == false)
        #expect(browser
            .build(for: .init(channel: F.channel, build: .init(run: 2, attempt: 2))) == nil)
        var stamp = F.stamp(run: 2)
        stamp["InstallerGitSHA"] = F.revision(99).rawValue
        let changedRevision = try UpdateBuildBrowser(
            catalog: catalog,
            installed: #require(InstalledBuild(infoDictionary: stamp)),
        )
        #expect(try #require(changedRevision.build(for: F.selection(channel: "pr-42", run: 2)))
            .isInstalled == false)
    }

    @Test func retiredAndPrunedSelectionsCannotResolveToInstallableBuilds() {
        let retired = UpdateBuildBrowser(
            catalog: F.catalog([2, 1], active: false),
            installed: F.installed(),
        )
        #expect(retired.channels.isEmpty)
        #expect(retired.build(for: F.selection(channel: "pr-42", run: 2)) == nil)
        let pruned = UpdateBuildBrowser(catalog: F.catalog([3]), installed: F.installed())
        #expect(pruned.build(for: F.selection(channel: "pr-42", run: 2)) == nil)
    }

    @Test func buildNotesDescribeOnlyTheSelectedReleaseAndKeepHistoryGapsExplicit() throws {
        let catalog = F.withChannels([.init(
            name: F.channel,
            active: true,
            releases: [F.release(4), F.release(3, historyChanged: true), F.release(1)],
        )])
        let browser = UpdateBuildBrowser(catalog: catalog, installed: F.installed(channel: "main"))
        let latest = try #require(browser.build(for: F.selection(channel: "pr-42", run: 4)))
        #expect(latest.changesSincePreviousBuild == .commits(F.release(4).commits))
        #expect(browser.build(for: F.selection(channel: "pr-42", run: 3))?
            .changesSincePreviousBuild == .rewritten)
        #expect(browser.build(for: F.selection(channel: "pr-42", run: 1))?
            .changesSincePreviousBuild == .unavailable)
    }
}
