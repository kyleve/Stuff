import Foundation

/// A validated catalog's installable builds for the installed app. Manual selection does not
/// change the installed channel or the automatic update decision.
public struct UpdateBuildBrowser: Sendable, Equatable {
    public struct Selection: Hashable, Sendable {
        public let channel: InstalledBuild.Channel
        public let build: InstalledBuild.BuildID

        public init(channel: InstalledBuild.Channel, build: InstalledBuild.BuildID) {
            self.channel = channel
            self.build = build
        }
    }

    public struct Channel: Identifiable, Sendable, Equatable {
        public let id: InstalledBuild.Channel
        public let latest: UpdateCatalog.Release
        public let previousReleases: [UpdateCatalog.Release]

        public var releases: [UpdateCatalog.Release] {
            [latest] + previousReleases
        }
    }

    public struct Build: Sendable, Equatable {
        public let selection: Selection
        public let release: UpdateCatalog.Release
        public let isInstalled: Bool
        /// This release's delta from its own predecessor, never a cross-channel comparison.
        public let changesSincePreviousBuild: UpdateCatalog.Changes
    }

    public let channels: [Channel]
    private let installed: InstalledBuild

    init(catalog: UpdateCatalog, installed: InstalledBuild) {
        self.installed = installed
        let app = catalog.apps.first {
            $0.id == installed.appID && $0.bundleIdentifier == installed.bundleIdentifier
        }
        channels = (app?.channels ?? []).compactMap { channel -> Channel? in
            guard channel.active, let latest = channel.releases.first else { return nil }
            return Channel(
                id: channel.name,
                latest: latest,
                previousReleases: Array(channel.releases.dropFirst()),
            )
        }.sorted { lhs, rhs in
            if (lhs.id == .main) != (rhs.id == .main) { return lhs.id == .main }
            if lhs.latest.id != rhs.latest.id { return lhs.latest.id > rhs.latest.id }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }

    public func channel(_ channel: InstalledBuild.Channel) -> Channel? {
        channels.first { $0.id == channel }
    }

    /// Resolve identities against the current snapshot, so retirement and retention remove actions.
    public func build(for selection: Selection) -> Build? {
        guard let release = channel(selection.channel)?.releases.first(where: {
            $0.id == selection.build
        }) else { return nil }
        let changes: UpdateCatalog.Changes = if release.baseSHA == nil {
            .unavailable
        } else if release.historyChanged {
            .rewritten
        } else {
            .commits(release.commits)
        }
        return Build(
            selection: selection,
            release: release,
            isInstalled: selection.channel == installed.publication?.channel &&
                selection.build == installed.publication?.build &&
                release.sha == installed.publication?.revision,
            changesSincePreviousBuild: changes,
        )
    }
}
