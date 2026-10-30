#if DEBUG
    import Foundation
    @_spi(Testing) import InstallerKit
    import SwiftUI

    /// Typed fixtures exercise the same cache, service, and model as a distributed build.
    @MainActor
    @_spi(Testing)
    public enum InstallerPreview {
        public enum Scenario: String, CaseIterable {
            case available = "Available"
            case current = "Current"
            case retired = "Retired"
            case rewritten = "RewrittenHistory"
            case unavailable = "MissingHistory"
            case offline = "Offline"
            case unpublished = "Unpublished"
            case missingDetails = "MissingDetails"
            case retiredWithoutMain = "RetiredWithoutMain"
            case local = "Local"
            case localDirty = "LocalDirty"
            case localUnknown = "LocalUnknown"
            case localOffline = "LocalOffline"
            case missingFeed = "MissingFeed"

            var isOffline: Bool {
                self == .offline || self == .localOffline
            }

            public var requiresRefresh: Bool {
                isOffline || self == .missingFeed
            }
        }

        public static var branding: AppUpdateBranding {
            AppUpdateBranding(name: "Example Dev", subtitle: "Your next idea, ready to explore.")
        }

        private final class MemoryPreferences: UpdatePreferencesStoring {
            var installerUpdates = UpdatePreferences(cached: nil)
        }

        public static let date = Date(timeIntervalSince1970: 1_800_000_000)
        public static let channel = InstalledBuild.Channel(rawValue: "pr-380")!
        public static let installedRevision = InstalledBuild.Revision(rawValue: String(
            repeating: "1",
            count: 40,
        ))!
        static let previousRevision = InstalledBuild.Revision(rawValue: String(
            repeating: "2",
            count: 40,
        ))!
        static let latestRevision = InstalledBuild.Revision(rawValue: String(
            repeating: "3",
            count: 40,
        ))!
        private static let appID = InstallerAppID(rawValue: "example")!
        private static let feedURL = URL(string: "https://updates.example.com/updates.json")!

        public static func model(_ scenario: Scenario) -> UpdateModel {
            let installed: InstalledBuild = switch scenario {
                case .local, .localOffline,
                     .missingFeed: localBuild(revision: .clean(installedRevision))
                case .localDirty: localBuild(revision: .dirty(installedRevision))
                case .localUnknown: localBuild(revision: .unavailable)
                case .available, .current, .retired, .rewritten, .unavailable, .offline,
                     .unpublished, .missingDetails, .retiredWithoutMain: distribution()
            }
            return model(
                catalog: catalog(scenario),
                installed: installed,
                failure: scenario == .missingFeed ? UpdateClient.FetchError.httpStatus(404) :
                    scenario.isOffline ? URLError(.notConnectedToInternet) : nil,
                cacheCatalog: scenario != .missingFeed,
            )
        }

        static func model(
            catalog: UpdateCatalog,
            installed: InstalledBuild,
            failure: (any Error)?,
            cacheCatalog: Bool,
        ) -> UpdateModel {
            let preferences = MemoryPreferences()
            preferences.installerUpdates = UpdatePreferences(cached: cacheCatalog ? .init(
                feedURL: installed.feedURL,
                checkedAt: date,
                catalog: catalog,
            ) : nil)
            return UpdateModel(service: UpdateService(
                installed: installed,
                preferences: preferences,
                client: Client(catalog: catalog, failure: failure),
                now: { date },
            ))
        }

        public static func distribution() -> InstalledBuild {
            installed(source: .published(.init(
                channel: channel,
                build: .init(run: 12, attempt: 1),
                revision: installedRevision,
            )))
        }

        public static func localBuild(revision: InstalledBuild.LocalRevision) -> InstalledBuild {
            installed(source: .local(revision))
        }

        private static func installed(source: InstalledBuild.Source) -> InstalledBuild {
            InstalledBuild(
                appID: appID,
                bundleIdentifier: "com.example.development",
                repositoryURL: URL(string: "https://github.com/example/Apps")!,
                source: source,
                feedURL: feedURL,
            )
        }

        public static func catalog(_ scenario: Scenario) -> UpdateCatalog {
            func release(
                run: UInt64,
                channel: InstalledBuild.Channel,
                revision: InstalledBuild.Revision,
                baseRevision: InstalledBuild.Revision?,
                subject: String,
            ) -> UpdateCatalog.Release {
                Self.release(
                    run: run,
                    channel: channel,
                    revision: revision,
                    baseRevision: baseRevision,
                    historyChanged: scenario == .rewritten && run == 14,
                    commits: [.init(sha: revision, subject: subject)],
                    buildDetails: scenario == .missingDetails ? nil : .init(
                        version: "0.9.2",
                        minimumOSVersion: "27.0",
                        sizeBytes: 48_300_000,
                    ),
                    pullRequestTitle: nil,
                )
            }
            let releases = [
                release(
                    run: 14,
                    channel: channel,
                    revision: latestRevision,
                    baseRevision: previousRevision,
                    subject: "Show update notes and an install action in Settings",
                ),
                release(
                    run: 13,
                    channel: channel,
                    revision: previousRevision,
                    baseRevision: installedRevision,
                    subject: "Publish main and labeled pull request builds",
                ),
                release(
                    run: 12,
                    channel: channel,
                    revision: installedRevision,
                    baseRevision: nil,
                    subject: "Add remote development installs",
                ),
            ]
            let selected: [UpdateCatalog.Release] = switch scenario {
                case .current: [releases[2]]
                case .unavailable: [releases[0]]
                case .available, .retired, .rewritten, .offline, .unpublished, .missingDetails,
                     .retiredWithoutMain, .local, .localDirty, .localUnknown,
                     .localOffline, .missingFeed: releases
            }
            return catalog(channels: scenario == .unpublished ? [] : [
                .init(
                    name: channel,
                    active: scenario != .retired && scenario != .retiredWithoutMain,
                    releases: selected,
                ),
                .init(
                    name: .main,
                    active: scenario != .retiredWithoutMain,
                    releases: [release(
                        run: 14,
                        channel: .main,
                        revision: latestRevision,
                        baseRevision: previousRevision,
                        subject: "Show update notes and an install action in Settings",
                    )],
                ),
            ])
        }

        static func catalog(channels: [UpdateCatalog.Channel]) -> UpdateCatalog {
            UpdateCatalog(schemaVersion: 3, apps: [.init(
                id: appID,
                name: "Example Dev",
                bundleIdentifier: "com.example.development",
                channels: channels,
            )])
        }

        static func release(
            run: UInt64,
            channel: InstalledBuild.Channel,
            revision: InstalledBuild.Revision,
            baseRevision: InstalledBuild.Revision?,
            historyChanged: Bool,
            commits: [UpdateCatalog.Commit],
            buildDetails: UpdateCatalog.BuildDetails?,
            pullRequestTitle: String?,
        ) -> UpdateCatalog.Release {
            UpdateCatalog.Release(
                id: .init(run: run, attempt: 1),
                sha: revision,
                publishedAt: date,
                manifestURL: feedURL.deletingLastPathComponent().appending(
                    path: "manifests/\(appID.rawValue)/\(channel.rawValue)/\(run)-1.plist",
                ),
                baseSHA: baseRevision,
                historyChanged: historyChanged,
                commits: commits,
                buildDetails: buildDetails,
                pullRequestTitle: pullRequestTitle,
            )
        }

        struct Client: UpdateFetching {
            let catalog: UpdateCatalog
            let failure: (any Error)?
            func fetch(from _: URL) async throws -> UpdateCatalog {
                if let failure { throw failure }
                return catalog
            }
        }
    }
#endif
