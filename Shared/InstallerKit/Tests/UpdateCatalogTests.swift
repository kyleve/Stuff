import Foundation
@_spi(Testing) @testable import InstallerKit
import Testing

struct UpdateCatalogTests {
    private typealias F = UpdateFixtures

    @Test func localBuildsNeverReceiveAutomaticUpdateOrRetirementAlerts() {
        for catalog in [F.catalog([2, 1]), F.catalog([2, 1], active: false), F.withChannels([])] {
            let availability = catalog.availability(for: F.localInstalled(status: "dirty"))
            #expect(availability == .local)
            #expect(!availability.needsAttention)
        }
    }

    @Test func decodesSignedBuildDetailsAndPreservesThemInTheCache() throws {
        let details = UpdateCatalog.BuildDetails(
            version: "0.9.2",
            minimumOSVersion: "27.0",
            sizeBytes: 48_300_000,
        )
        let catalog = F.withChannels([.init(
            name: F.channel,
            active: true,
            releases: [
                F.release(2, buildDetails: details),
                F.release(1),
            ],
        )])
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(UpdateCatalog.self, from: data)
        try decoded.validate(feedURL: F.feedURL)
        #expect(decoded.apps[0].channels[0].releases[0].buildDetails == details)
        guard case let .available(update) = decoded.availability(for: F.installed()) else {
            Issue.record("Expected an available build"); return
        }
        #expect(update.release.buildDetails == details)
        #expect(decoded == catalog)
    }

    @Test func olderFeedsWithoutBuildDetailsRemainReadable() throws {
        let data = try JSONEncoder().encode(F.catalog([2, 1]))
        #expect(!String(decoding: data, as: UTF8.self).contains("buildDetails"))
        let decoded = try JSONDecoder().decode(UpdateCatalog.self, from: data)
        try decoded.validate(feedURL: F.feedURL)
        #expect(decoded.apps[0].channels[0].releases[0].buildDetails == nil)
    }

    @Test(arguments: [
        UpdateCatalog.BuildDetails(version: "release", minimumOSVersion: "27.0", sizeBytes: 1),
        .init(version: "1.2.3.4", minimumOSVersion: "27.0", sizeBytes: 1),
        .init(version: "1.0", minimumOSVersion: "27.0\n", sizeBytes: 1),
        .init(version: "1.0", minimumOSVersion: "", sizeBytes: 1),
        .init(version: "1.0", minimumOSVersion: "27.0", sizeBytes: 0),
        .init(version: "1.0", minimumOSVersion: "27.0", sizeBytes: -1),
    ])
    func rejectsInvalidSignedBuildDetails(_ details: UpdateCatalog.BuildDetails) throws {
        let catalog = F.withChannels([.init(
            name: F.channel,
            active: true,
            releases: [F.release(2, buildDetails: details)],
        )])
        #expect(throws: UpdateCatalog.ValidationError.self) {
            try catalog.validate(feedURL: F.feedURL)
        }
    }

    @Test func installLinkTargetsTheExactManifestThroughTheSystemInstaller() throws {
        let release = F.release(2)
        let components = try #require(URLComponents(
            url: release.installURL,
            resolvingAgainstBaseURL: false,
        ))
        #expect(components.scheme == "itms-services")
        #expect(components.host == "")
        #expect(components.queryItems == [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: release.manifestURL.absoluteString),
        ])
        #expect(release.manifestURL.lastPathComponent == "2-1.plist")
    }

    @Test func acceptsCustomPagesDomainAndSubdirectoryOnlyAtTheSignedFeedLocation() throws {
        let customFeed = try #require(URL(string: "https://builds.example.org/where/updates.json"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(F.catalog([2, 1]))
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(
            of: "https://updates.example.com/",
            with: "https://builds.example.org/where/",
        )
        let catalog = try JSONDecoder().decode(UpdateCatalog.self, from: Data(text.utf8))
        try catalog.validate(feedURL: customFeed)
        #expect(throws: UpdateCatalog.ValidationError.self) {
            try catalog.validate(feedURL: F.feedURL)
        }
    }

    @Test func combinesAllIncomingCommitsAcrossSkippedBuilds() throws {
        let catalog = F.catalog([4, 3, 2, 1])
        try catalog.validate(feedURL: F.feedURL)
        guard case let .available(update) = catalog.availability(for: F.installed()) else {
            Issue.record("Expected an update"); return
        }
        #expect(update.release.id.run == 4)
        #expect(update.changes == .commits([4, 3, 2].map { F.release($0).commits[0] }))
    }

    @Test func equalOrOlderPublishedBuildsDoNotOfferDowngrades() {
        #expect(F.catalog([1]).availability(for: F.installed()) == .current)
        #expect(F.catalog([1]).availability(for: F.installed(run: 2)) == .current)
    }

    @Test func unknownBaselineDoesNotClaimCompleteNotes() {
        #expect(F.catalog([3, 2]).availability(for: F.installed()) == .available(.init(
            release: F.release(3),
            changes: .unavailable,
        )))
    }

    @Test func rewrittenHistoryIsExplicit() {
        let rewritten = F.release(3, historyChanged: true)
        let catalog = F.withChannels([
            .init(name: F.channel, active: true, releases: [rewritten, F.release(2), F.release(1)]),
        ])
        #expect(catalog.availability(for: F.installed()) == .available(.init(
            release: rewritten,
            changes: .rewritten,
        )))
    }

    @Test func missingGitObjectsAreUnavailableRatherThanClaimedAsARebase() {
        let original = F.release(2)
        let latest = UpdateCatalog.Release(
            id: original.id,
            sha: original.sha,
            publishedAt: original.publishedAt,
            manifestURL: original.manifestURL,
            baseSHA: nil,
            historyChanged: true,
            commits: [],
            buildDetails: nil,
        )
        let catalog = F.withChannels([
            .init(name: F.channel, active: true, releases: [latest, F.release(1)]),
        ])
        #expect(catalog.availability(for: F.installed()) == .available(.init(
            release: latest,
            changes: .unavailable,
        )))
    }

    @Test func missingLinkIsNotShownAsComplete() {
        #expect(F.catalog([3, 1]).availability(for: F.installed()) == .available(.init(
            release: F.release(3),
            changes: .unavailable,
        )))
    }

    @Test func retiredChannelOffersMainExplicitlyEvenIfOlder() throws {
        let catalog = try F.withChannels([
            .init(name: F.channel, active: false, releases: [F.release(2)]),
            .init(
                name: #require(.init(rawValue: "main")),
                active: true,
                releases: [F.release(1, channel: "main")],
            ),
        ])
        try catalog.validate(feedURL: F.feedURL)
        #expect(catalog.availability(for: F.installed(run: 2)) == .retired(main: F.release(
            1,
            channel: "main",
        )))
        #expect(F.catalog([], active: false)
            .availability(for: F.installed()) == .retired(main: nil))
        #expect(catalog.availability(for: F.installed(channel: "pr-99")) == .unpublished)
    }

    @Test func rejectsUnknownSchemaDuplicatesAndWrongOrdering() {
        let valid = F.catalog([2, 1])
        let invalid = [
            UpdateCatalog(schemaVersion: 99, apps: valid.apps),
            F.withChannels(valid.apps[0].channels + valid.apps[0].channels),
            F.catalog([1, 2]),
            F.catalog([2, 2]),
            F.catalog([]),
        ]
        for catalog in invalid {
            #expect(throws: UpdateCatalog.ValidationError.self) {
                try catalog.validate(feedURL: F.feedURL)
            }
        }
    }

    @Test(arguments: [
        "http://updates.example.com/manifests/where/pr-42/1-1.plist",
        "https://evil.example/manifests/where/pr-42/1-1.plist",
        "https://updates.example.com/manifests/where/pr-42/1-1.plist?next=evil",
        "https://updates.example.com/manifests/where/main/1-1.plist",
        "https://updates.example.com/manifests/where/pr-42/2-1.plist",
        "https://user@updates.example.com/manifests/where/pr-42/1-1.plist",
        "https://updates.example.com:443/manifests/where/pr-42/1-1.plist",
        "https://updates.example.com/manifests/where/pr-42/1-1.plist#fragment",
        "itms-services://?action=download-manifest&url=https://evil.example/manifest.plist"
    ])
    func rejectsUntrustedInstallationDestinations(_ url: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(F.catalog([1]))
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(
            of: "https://updates.example.com/manifests/where/pr-42/1-1.plist",
            with: url,
        )
        let decoded = try JSONDecoder().decode(UpdateCatalog.self, from: Data(text.utf8))
        #expect(throws: UpdateCatalog.ValidationError.self) {
            try decoded.validate(feedURL: F.feedURL)
        }
    }

    @Test func appsWithMatchingChannelNamesAndRunsStayIsolated() throws {
        let otherID = try #require(InstallerAppID(rawValue: "example"))
        let foreign = try UpdateCatalog.App(
            id: otherID,
            name: "Example Dev",
            bundleIdentifier: "com.example.development",
            channels: [
                .init(name: F.channel, active: true, releases: [F.release(9, appID: "example")]),
                .init(
                    name: #require(.init(rawValue: "main")),
                    active: true,
                    releases: [F.release(
                        10,
                        appID: "example",
                        channel: "main",
                    )],
                ),
            ],
        )
        let catalog = UpdateCatalog(schemaVersion: 3, apps: [foreign] + F.catalog([2, 1]).apps)
        try catalog.validate(feedURL: F.feedURL)
        guard case let .available(update) = catalog.availability(for: F.installed())
        else { Issue.record("Expected this app's update"); return }
        #expect(update.release == F.release(2))
        let retired = UpdateCatalog(
            schemaVersion: 3,
            apps: [foreign] + F.catalog([1], active: false).apps,
        )
        #expect(retired.availability(for: F.installed()) == .retired(main: nil))
        #expect(UpdateCatalog(schemaVersion: 3, apps: [foreign])
            .availability(for: F.installed()) == .unpublished)
        var stamp = F.stamp()
        stamp["InstallerAppID"] = "example"
        // Matching app IDs alone cannot cross bundle identities.
        #expect(try catalog
            .availability(for: #require(InstalledBuild(infoDictionary: stamp))) == .unpublished)
        stamp["CFBundleIdentifier"] = "com.example.development"
        guard case let .available(other) = try catalog
            .availability(for: #require(InstalledBuild(infoDictionary: stamp)))
        else { Issue.record("Expected the other app's update"); return }
        #expect(other.release.id.run == 9)
    }

    @Test func duplicateAppsAndCrossAppManifestsFailValidation() throws {
        let app = try #require(F.catalog([2, 1]).apps.first)
        let invalid = try [
            UpdateCatalog(schemaVersion: 3, apps: [app, app]),
            UpdateCatalog(
                schemaVersion: 3,
                apps: [.init(
                    id: #require(InstallerAppID(rawValue: "other")),
                    name: "Other",
                    bundleIdentifier: "com.other.development",
                    channels: app.channels,
                )],
            ),
            UpdateCatalog(
                schemaVersion: 3,
                apps: [app, .init(
                    id: #require(InstallerAppID(rawValue: "other")),
                    name: "Other",
                    bundleIdentifier: app.bundleIdentifier,
                    channels: [],
                )],
            ),
        ]
        for catalog in invalid {
            #expect(throws: UpdateCatalog.ValidationError.self) {
                try catalog.validate(feedURL: F.feedURL)
            }
        }
    }
}
