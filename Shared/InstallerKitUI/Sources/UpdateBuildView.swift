import InstallerKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct UpdateBuildView: View {
    let model: UpdateModel
    let branding: AppUpdateBranding
    let selection: UpdateBuildBrowser.Selection

    var body: some View {
        UpdateBrowserPage(model: model) {
            if let build = model.state.snapshot?.browser.build(for: selection) {
                UpdateSelectedBuild(build: build, installed: model.installed, branding: branding)
            } else {
                UpdateNoticeCard(
                    title: .installerBuildUnavailable,
                    message: .installerBuildUnavailableMessage,
                )
            }
        }
        .navigationTitle(String(localized: .installerBuildDetails))
    }
}

private struct UpdateSelectedBuild: View {
    let build: UpdateBuildBrowser.Build
    let installed: InstalledBuild
    let branding: AppUpdateBranding

    var body: some View {
        UpdateHero(
            branding: branding,
            channelLabel: Text(verbatim: build.selection.channel.rawValue),
        ) {
            UpdateSelectedBuildAction(build: build)
        }
        UpdateBuildHistoryLink(channel: build.selection.channel)
        UpdateBuildSummary(release: build.release)
        UpdateChanges(
            changes: build.changesSincePreviousBuild,
            installed: installed,
            scope: .previousBuild,
        )
        UpdateBuildInformation(
            channel: build.selection.channel,
            release: build.release,
            installed: installed,
        )
    }
}

private struct UpdateSelectedBuildAction: View {
    let build: UpdateBuildBrowser.Build
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        Text(
            .installerBuildNumber(
                "\(build.release.id.run).\(build.release.id.attempt)",
            ),
        )
        .font(stylesheet.hero.subtitleFont)
        .foregroundStyle(.secondary)
        if build.isInstalled {
            Label(
                String(localized: .installerInstalled),
                systemSymbol: .checkmarkCircle,
            )
            .font(stylesheet.hero.subtitleFont)
        } else {
            UpdateInstallLink(title: .installerInstallBuild, release: build.release)
        }
    }
}

private struct UpdateBuildHistoryLink: View {
    let channel: InstalledBuild.Channel
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        NavigationLink(value: UpdateBrowserView.Route.history(channel)) {
            Label(
                String(localized: .installerBuildHistory),
                systemSymbol: .clockArrowCirclepath,
            )
            .font(stylesheet.browser.actionFont)
            .frame(maxWidth: .infinity, minHeight: stylesheet.browser.minimumHeight)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }
}

#if DEBUG
    extension UpdateBuildView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            // Fresh cached catalogs and a fixed fixture clock make sizing synchronous.
            // Final settling still covers the native navigation chrome.
            for scenario in InstallerBrowserPreview.BuildScenario.allCases {
                SnapshotCase(
                    name: scenario.rawValue,
                    configurations: scenario == .otherChannel ? .fullContentScreenRepresentative :
                        .fullContentPhoneLightDark,
                    measurementReadiness: .immediate,
                ) {
                    InstallerBrowserPreview.Navigation(
                        route: .build(scenario.selection),
                        model: scenario.model,
                    )
                }
            }
        }
    }

    #Preview { UpdateBuildView.snapshotPreviews }
#endif
