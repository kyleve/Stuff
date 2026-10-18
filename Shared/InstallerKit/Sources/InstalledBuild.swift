import Foundation

/// Signed app configuration with an explicit local or published build identity.
/// The host owns audience and lifecycle eligibility.
public struct InstalledBuild: Sendable, Equatable {
    public struct Publication: Sendable, Equatable {
        public let channel: Channel
        public let build: BuildID
        public let revision: Revision
    }

    /// Local checkouts can contain changes or lack Git metadata. Neither is a published build.
    public enum LocalRevision: Sendable, Equatable {
        case clean(Revision)
        case dirty(Revision)
        case unavailable
    }

    public enum Source: Sendable, Equatable {
        case local(LocalRevision)
        case published(Publication)
    }

    /// Channel names are a single string in the public feed, not a keyed object.
    public struct Channel: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: String

        public static let main = Channel(rawValue: "main")!

        public init?(rawValue: String) {
            guard rawValue
                .range(of: #"\A(main|pr-[1-9][0-9]*)\z"#, options: .regularExpression) != nil
            else { return nil }
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let channel = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid update channel",
                )
            }
            self = channel
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// GitHub's run and attempt identify and order builds without ordering commit hashes.
    public struct BuildID: Codable, Hashable, Comparable, Sendable {
        public let run: UInt64
        public let attempt: UInt64

        public init(run: UInt64, attempt: UInt64) {
            self.run = run
            self.attempt = attempt
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.run == rhs.run ? lhs.attempt < rhs.attempt : lhs.run < rhs.run
        }
    }

    /// Full commit hashes use the feed's single-string wire shape.
    public struct Revision: RawRepresentable, Codable, Hashable, Sendable {
        public let rawValue: String

        public init?(rawValue: String) {
            guard rawValue.range(of: #"\A[0-9a-f]{40}\z"#, options: .regularExpression) != nil
            else { return nil }
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let revision = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid commit",
                )
            }
            self = revision
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public let appID: InstallerAppID
    public let bundleIdentifier: String
    public let repositoryURL: URL
    public let source: Source
    public let feedURL: URL

    public var publication: Publication? {
        switch source {
            case .local: nil
            case let .published(publication): publication
        }
    }

    public init?(infoDictionary info: [String: String]) {
        guard let appID = info["InstallerAppID"].flatMap(InstallerAppID.init(rawValue:)),
              let bundleIdentifier = info["CFBundleIdentifier"],
              bundleIdentifier.range(
                  of: #"\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z"#,
                  options: .regularExpression,
              ) != nil,
              let repositoryURL = info["InstallerRepositoryURL"].flatMap(URL.init(string:)),
              repositoryURL.absoluteString.range(
                  of: #"\Ahttps://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z"#,
                  options: .regularExpression,
              ) != nil,
              let feedURL = info["InstallerFeedURL"].flatMap(URL.init(string:)),
              feedURL.scheme == "https", feedURL.host != nil,
              feedURL.user == nil, feedURL.password == nil, feedURL.fragment == nil,
              feedURL.port == nil, feedURL.query == nil,
              feedURL.lastPathComponent == "updates.json",
              let source = Self.source(from: info)
        else { return nil }
        self.appID = appID
        self.bundleIdentifier = bundleIdentifier
        self.repositoryURL = repositoryURL
        self.source = source
        self.feedURL = feedURL
    }

    private static func source(from info: [String: String]) -> Source? {
        let revision = info["InstallerGitSHA"].flatMap(Revision.init(rawValue:))
        // Local is an explicit build setting, never a fallback for an incomplete CI stamp.
        if info["InstallerChannel"] == "local" {
            guard let revision else { return .local(.unavailable) }
            switch info["InstallerGitStatus"] {
                case .some("clean"): return .local(.clean(revision))
                case .some("dirty"): return .local(.dirty(revision))
                case .some, .none: return .local(.unavailable)
            }
        }
        guard info["InstallerGitStatus"] == "clean",
              let channel = info["InstallerChannel"].flatMap(Channel.init(rawValue:)),
              let run = info["InstallerRun"].flatMap(UInt64.init), run > 0,
              let attempt = info["InstallerAttempt"].flatMap(UInt64.init), attempt > 0,
              let revision
        else { return nil }
        return .published(Publication(
            channel: channel,
            build: BuildID(run: run, attempt: attempt),
            revision: revision,
        ))
    }

    public func commitURL(for revision: Revision) -> URL {
        repositoryURL.appending(path: "commit").appending(path: revision.rawValue)
    }
}
