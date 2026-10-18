import Foundation
@testable import InstallerKit
import Testing

struct InstalledBuildTests {
    @Test func requiresCompleteCleanPublishedStamps() {
        let stamp = UpdateFixtures.stamp()
        #expect(InstalledBuild(infoDictionary: stamp)?.publication?.channel.rawValue == "pr-42")
        for key in stamp.keys {
            var missing = stamp
            missing.removeValue(forKey: key)
            #expect(InstalledBuild(infoDictionary: missing) == nil)
        }
    }

    @Test func rejectsMalformedPublishedIdentities() {
        let invalid = [
            "InstallerGitStatus": "dirty",
            "InstallerAppID": "../where",
            "CFBundleIdentifier": "",
            "InstallerRepositoryURL": "https://github.com/fixture/Stuff?next=other",
            "InstallerChannel": "pr-0",
            "InstallerRun": "0",
            "InstallerAttempt": "-1",
            "InstallerGitSHA": "123456789abc",
            "InstallerFeedURL": "http://example.com",
        ]
        for (key, value) in invalid {
            var stamp = UpdateFixtures.stamp()
            stamp[key] = value
            #expect(InstalledBuild(infoDictionary: stamp) == nil)
        }
    }

    @Test func localIdentityKeepsCleanDirtyAndUnavailableRevisionsExplicit() throws {
        let clean = UpdateFixtures.localInstalled()
        let dirty = UpdateFixtures.localInstalled(status: "dirty")
        #expect(clean.source == .local(.clean(UpdateFixtures.revision(1))))
        #expect(dirty.source == .local(.dirty(UpdateFixtures.revision(1))))
        #expect(clean.publication == nil)
        #expect(dirty.publication == nil)
        for key in ["InstallerGitSHA", "InstallerGitStatus"] {
            for value in ["unknown", "invalid", nil] as [String?] {
                var stamp = UpdateFixtures.localStamp()
                stamp[key] = value
                let installed = try #require(InstalledBuild(infoDictionary: stamp))
                #expect(installed.source == .local(.unavailable))
            }
        }
        var withoutRun = UpdateFixtures.localStamp()
        withoutRun.removeValue(forKey: "InstallerRun")
        withoutRun.removeValue(forKey: "InstallerAttempt")
        #expect(InstalledBuild(infoDictionary: withoutRun) == clean)
    }

    @Test func localStillRequiresExplicitChannelAndValidAppConfiguration() {
        for key in [
            "InstallerChannel",
            "InstallerAppID",
            "CFBundleIdentifier",
            "InstallerRepositoryURL",
            "InstallerFeedURL",
        ] {
            var stamp = UpdateFixtures.localStamp()
            stamp.removeValue(forKey: key)
            #expect(InstalledBuild(infoDictionary: stamp) == nil)
            stamp[key] = key == "InstallerAppID" ? "../where" : "unknown"
            #expect(InstalledBuild(infoDictionary: stamp) == nil)
        }
        var unsafe = UpdateFixtures.localStamp()
        unsafe["InstallerFeedURL"] = "http://updates.example.com/updates.json"
        #expect(InstalledBuild(infoDictionary: unsafe) == nil)
        #expect(InstalledBuild.Channel(rawValue: "local") == nil)
    }

    @Test func identitiesRejectTrailingLineBreaks() {
        #expect(InstalledBuild.Channel(rawValue: "main\n") == nil)
        #expect(InstalledBuild
            .Revision(rawValue: UpdateFixtures.revision(1).rawValue + "\n") == nil)
    }

    @Test func buildOrderingIncludesReruns() {
        #expect(InstalledBuild.BuildID(run: 100, attempt: 1) < .init(run: 100, attempt: 2))
        #expect(InstalledBuild.BuildID(run: 100, attempt: 5) < .init(run: 101, attempt: 1))
    }

    @Test func repositoryLinksComeFromTheSignedAppIdentity() throws {
        var stamp = UpdateFixtures.stamp()
        stamp["InstallerAppID"] = "another-app"
        stamp["CFBundleIdentifier"] = "com.other.development"
        stamp["InstallerRepositoryURL"] = "https://github.com/another/Apps"
        let installed = try #require(InstalledBuild(infoDictionary: stamp))
        let publication = try #require(installed.publication)
        #expect(installed.appID.rawValue == "another-app")
        #expect(installed.commitURL(for: publication.revision).absoluteString ==
            "https://github.com/another/Apps/commit/" + publication.revision.rawValue)
    }
}
