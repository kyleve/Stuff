import Foundation
@testable import InstallerKit
import Testing

struct InstalledBuildTests {
    @Test(arguments: ["1", "428", "184467440737095516160"])
    func channelRetainsPullRequestNumberWithCompatibleWireFormat(number: String) throws {
        let identity = try #require(InstalledBuild.Channel.PullRequestNumber(rawValue: number))
        let channel = InstalledBuild.Channel.pullRequest(identity)
        let wireValue = "pr-" + number
        #expect(channel.rawValue == wireValue)
        #expect(InstalledBuild.Channel(rawValue: wireValue) == channel)
        let data = try JSONEncoder().encode(wireValue)
        #expect(try JSONEncoder().encode(channel) == data)
        #expect(try JSONDecoder().decode(InstalledBuild.Channel.self, from: data) == channel)
        #expect(UpdateFixtures.localInstalled().pullRequestURL(for: channel)?.absoluteString ==
            "https://github.com/fixture/Stuff/pull/" + number)
    }

    @Test func mainChannelKeepsCompatibleWireFormat() throws {
        let data = Data(#""main""#.utf8)
        #expect(InstalledBuild.Channel.main.rawValue == "main")
        #expect(InstalledBuild.Channel(rawValue: "main") == .main)
        #expect(try JSONEncoder().encode(InstalledBuild.Channel.main) == data)
        #expect(try JSONDecoder().decode(InstalledBuild.Channel.self, from: data) == .main)
    }

    @Test(arguments: ["", "0", "01", "-1", "+1", "1.0", "42\n", "４２", "42/path"])
    func rejectsMalformedPullRequestNumbers(number: String) throws {
        #expect(InstalledBuild.Channel.PullRequestNumber(rawValue: number) == nil)
        let channel = "pr-" + number
        #expect(InstalledBuild.Channel(rawValue: channel) == nil)
        let data = try JSONEncoder().encode(channel)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(InstalledBuild.Channel.self, from: data)
        }
    }

    @Test(arguments: ["local", "PR-42", "pr42", "pr-", "main-42", "pr-42-extra", " main", "main\n"])
    func rejectsMalformedChannelNames(channel: String) throws {
        #expect(InstalledBuild.Channel(rawValue: channel) == nil)
        let data = try JSONEncoder().encode(channel)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(InstalledBuild.Channel.self, from: data)
        }
    }

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
        #expect(installed.pullRequestURL(for: publication.channel)?.absoluteString ==
            "https://github.com/another/Apps/pull/42")
        let otherChannel = try #require(InstalledBuild.Channel(rawValue: "pr-417"))
        #expect(installed.pullRequestURL(for: otherChannel)?.absoluteString ==
            "https://github.com/another/Apps/pull/417")
        #expect(installed.pullRequestURL(for: .main) == nil)
        #expect(UpdateFixtures.localInstalled().pullRequestURL(for: otherChannel)?
            .lastPathComponent == "417")
    }
}
