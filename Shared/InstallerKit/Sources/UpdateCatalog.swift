import Foundation

/// Versioned public feed. Retained releases carry the complete incoming commits from their
/// predecessor.
public struct UpdateCatalog: Codable, Sendable, Equatable {
    /// Optional display metadata from the signed IPA. Older releases omit this block.
    public struct BuildDetails: Codable, Sendable, Equatable {
        public let version: String
        public let minimumOSVersion: String
        public let sizeBytes: Int64

        fileprivate var isValid: Bool {
            [version, minimumOSVersion]
                .allSatisfy(InstallerPattern.version.matches) && sizeBytes > 0
        }
    }

    public struct Commit: Codable, Sendable, Equatable, Identifiable {
        public let sha: InstalledBuild.Revision
        public let subject: String
        public var id: InstalledBuild.Revision {
            sha
        }
    }

    public struct Release: Codable, Sendable, Equatable, Identifiable {
        public let id: InstalledBuild.BuildID
        public let sha: InstalledBuild.Revision
        public let publishedAt: Date
        public let manifestURL: URL
        public let baseSHA: InstalledBuild.Revision?
        public let historyChanged: Bool
        public let commits: [Commit]
        public let buildDetails: BuildDetails?

        /// The system installer reads the validated HTTPS manifest for this exact build.
        public var installURL: URL {
            var components = URLComponents()
            components.scheme = "itms-services"
            components.host = ""
            components.queryItems = [
                URLQueryItem(name: "action", value: "download-manifest"),
                URLQueryItem(name: "url", value: manifestURL.absoluteString),
            ]
            return components.url!
        }
    }

    public struct Channel: Codable, Sendable, Equatable {
        public let name: InstalledBuild.Channel
        public let active: Bool
        public let releases: [Release]
    }

    public enum Changes: Sendable, Equatable {
        case commits([Commit])
        case rewritten
        case unavailable
    }

    public struct Update: Sendable, Equatable {
        public let release: Release
        public let changes: Changes
    }

    public enum Availability: Sendable, Equatable {
        case local
        case current
        case available(Update)
        case retired(main: Release?)
        case unpublished

        public var needsAttention: Bool {
            switch self {
                case .available, .retired: true
                case .local, .current, .unpublished: false
            }
        }
    }

    public enum ValidationError: Error {
        case invalidCatalog
    }

    public struct App: Codable, Sendable, Equatable {
        public let id: InstallerAppID
        public let name: String
        public let bundleIdentifier: String
        public let channels: [Channel]
    }

    public let schemaVersion: Int
    public let apps: [App]

    public func validate(feedURL: URL) throws {
        guard schemaVersion == 3, Set(apps.map(\.id)).count == apps.count,
              Set(apps.map(\.bundleIdentifier)).count == apps.count,
              feedURL.scheme == "https", feedURL.host != nil,
              feedURL.user == nil, feedURL.password == nil, feedURL.port == nil,
              feedURL.query == nil, feedURL.fragment == nil,
              feedURL.lastPathComponent == "updates.json"
        else {
            throw ValidationError.invalidCatalog
        }
        for app in apps {
            guard !app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  InstallerPattern.bundleIdentifier.matches(app.bundleIdentifier),
                  Set(app.channels.map(\.name)).count == app.channels.count
            else { throw ValidationError.invalidCatalog }
            for channel in app.channels {
                guard !channel.active || !channel.releases.isEmpty,
                      Set(channel.releases.map(\.id)).count == channel.releases.count
                else { throw ValidationError.invalidCatalog }
                for (index, release) in channel.releases.enumerated() {
                    let expectedManifest = feedURL.deletingLastPathComponent()
                        .appending(
                            path: "manifests/\(app.id.rawValue)/\(channel.name.rawValue)/\(release.id.run)-\(release.id.attempt).plist",
                        )
                    guard release.id.run > 0, release.id.attempt > 0,
                          release.publishedAt.timeIntervalSince1970.isFinite,
                          release.manifestURL.absoluteString == expectedManifest.absoluteString,
                          release.buildDetails?.isValid != false,
                          Set(release.commits.map(\.sha)).count == release.commits.count,
                          index == 0 || channel.releases[index - 1].id > release.id
                    else { throw ValidationError.invalidCatalog }
                }
            }
        }
    }

    public func availability(for installed: InstalledBuild) -> Availability {
        guard let publication = installed.publication else { return .local }
        guard let app = apps.first(where: {
            $0.id == installed.appID && $0.bundleIdentifier == installed.bundleIdentifier
        }) else { return .unpublished }
        let channels = app.channels
        guard let channel = channels.first(where: { $0.name == publication.channel })
        else { return .unpublished }
        guard channel.active else {
            return .retired(main: channels
                .first(where: { $0.name.rawValue == "main" && $0.active })?.releases.first)
        }
        guard let latest = channel.releases.first else { return .unpublished }
        guard latest.id > publication.build else { return .current }
        guard let baseline = channel.releases
            .firstIndex(where: { $0.id == publication.build && $0.sha == publication.revision })
        else {
            return .available(Update(release: latest, changes: .unavailable))
        }
        let incoming = channel.releases.prefix(baseline)
        if incoming.contains(where: { $0.baseSHA == nil }) {
            return .available(Update(release: latest, changes: .unavailable))
        }
        if incoming.contains(where: \.historyChanged) {
            return .available(Update(release: latest, changes: .rewritten))
        }
        var prior = publication.revision
        for release in incoming.reversed() {
            guard release.baseSHA == prior else {
                return .available(Update(release: latest, changes: .unavailable))
            }
            prior = release.sha
        }
        var seen = Set<InstalledBuild.Revision>()
        let commits = incoming.flatMap(\.commits).filter { seen.insert($0.sha).inserted }
        return .available(Update(release: latest, changes: .commits(commits)))
    }
}
