#if DEBUG
    @_spi(Testing) import InstallerKit
    import SwiftUI

    /// Browser fixtures include an older PR build and retained history below the installed build.
    @MainActor
    enum InstallerBrowserPreview {
        enum Scenario: String, CaseIterable {
            case available = "Available"
            case offline = "Offline"
            case empty = "Empty"
            case retired = "Retired"
            case local = "Local"
        }

        enum BuildScenario: String, CaseIterable {
            case otherChannel = "OtherChannel"
            case older = "OlderBuild"
            case installed = "Installed"
            case unavailable = "Unavailable"
            case rewritten = "RewrittenHistory"
            case missingDetails = "MissingDetails"

            @MainActor var selection: UpdateBuildBrowser.Selection {
                switch self {
                    case .otherChannel: InstallerBrowserPreview.selection(
                            channel: InstallerBrowserPreview.otherChannel,
                            run: 9,
                        )
                    case .older: InstallerBrowserPreview.selection(
                            channel: InstallerPreview.channel,
                            run: 11,
                        )
                    case .installed: InstallerBrowserPreview.selection(
                            channel: InstallerPreview.channel,
                            run: 12,
                        )
                    case .unavailable, .rewritten, .missingDetails:
                        InstallerBrowserPreview.selection(
                            channel: InstallerPreview.channel,
                            run: 14,
                        )
                }
            }

            @MainActor var model: UpdateModel {
                switch self {
                    case .otherChannel, .older,
                         .installed: InstallerBrowserPreview.model(.available)
                    case .unavailable: InstallerBrowserPreview.model(.retired)
                    case .rewritten: InstallerPreview.model(.rewritten)
                    case .missingDetails: InstallerPreview.model(.missingDetails)
                }
            }
        }

        static let otherChannel = InstalledBuild.Channel(rawValue: "pr-417")!

        nonisolated static func selection(
            channel: InstalledBuild.Channel,
            run: UInt64,
        ) -> UpdateBuildBrowser.Selection {
            .init(channel: channel, build: .init(run: run, attempt: 1))
        }

        static func model(_ scenario: Scenario) -> UpdateModel {
            InstallerPreview.model(
                catalog: catalog(scenario),
                installed: scenario == .local ? InstallerPreview.localBuild(
                    revision: .dirty(InstallerPreview.installedRevision),
                ) : InstallerPreview.distribution(),
                isOffline: scenario == .offline,
            )
        }

        static func catalog(_ scenario: Scenario) -> UpdateCatalog {
            guard scenario != .empty else { return InstallerPreview.catalog(.unpublished) }
            let source = InstallerPreview.catalog(.available)
            let olderRevision = InstalledBuild.Revision(rawValue: String(
                repeating: "4",
                count: 40,
            ))!
            let otherRevision = InstalledBuild.Revision(rawValue: String(
                repeating: "5",
                count: 40,
            ))!
            let channels = source.apps[0].channels.map { channel in
                guard channel.name == InstallerPreview.channel else { return channel }
                let releases = channel.releases.map { release in
                    guard release.id == InstalledBuild.BuildID(run: 12, attempt: 1)
                    else { return release }
                    return UpdateCatalog.Release(
                        id: release.id,
                        sha: release.sha,
                        publishedAt: release.publishedAt,
                        manifestURL: release.manifestURL,
                        baseSHA: olderRevision,
                        historyChanged: release.historyChanged,
                        commits: release.commits,
                        buildDetails: release.buildDetails,
                    )
                }
                let older = InstallerPreview.release(
                    run: 11,
                    channel: channel.name,
                    revision: olderRevision,
                    baseRevision: nil,
                    historyChanged: false,
                    commits: [],
                    buildDetails: releases[2].buildDetails,
                )
                return UpdateCatalog.Channel(
                    name: channel.name,
                    active: scenario != .retired,
                    releases: releases + [older],
                )
            }
            let other = InstallerPreview.release(
                run: 9,
                channel: otherChannel,
                revision: otherRevision,
                baseRevision: InstallerPreview.previousRevision,
                historyChanged: false,
                commits: [.init(sha: otherRevision, subject: "Explore a new timeline layout")],
                buildDetails: source.apps[0].channels[0].releases[0].buildDetails,
            )
            return InstallerPreview.catalog(channels: channels + [.init(
                name: otherChannel,
                active: true,
                releases: [other],
            )])
        }

        static func navigation(to route: UpdateBrowserView.Route, model: UpdateModel) -> some View {
            NavigationStack(path: .constant([route])) {
                UpdateChannelsView(model: model)
                    .updateBrowserDestinations(model: model, branding: InstallerPreview.branding)
            }
            .installerBroadwayRoot()
        }
    }
#endif
