import InstallerKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct UpdateBuildView: View {
    let model: UpdateModel
    let branding: AppUpdateBranding
    let selection: UpdateBuildBrowser.Selection
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateBrowserPage(model: model) {
            if let build = model.state.snapshot?.browser.build(for: selection) {
                UpdateHero(
                    branding: branding,
                    channelLabel: Text(verbatim: selection.channel.rawValue),
                ) {
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
                NavigationLink(value: UpdateBrowserView.Route.history(selection.channel)) {
                    Label(
                        String(localized: .installerBuildHistory),
                        systemSymbol: .clockArrowCirclepath,
                    )
                    .font(stylesheet.browser.actionFont)
                    .frame(maxWidth: .infinity, minHeight: stylesheet.browser.minimumHeight)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                UpdateBuildSummary(release: build.release)
                UpdateChanges(
                    changes: build.changesSincePreviousBuild,
                    installed: model.installed,
                    scope: .previousBuild,
                )
                UpdateBuildInformation(
                    channel: selection.channel,
                    release: build.release,
                    installed: model.installed,
                )
            } else {
                UpdateCard(title: .installerBuildUnavailable) {
                    Text(.installerBuildUnavailableMessage)
                        .font(stylesheet.card.bodyFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: .installerBuildDetails))
    }
}

#if DEBUG
    extension UpdateBuildView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in InstallerBrowserPreview.BuildScenario.allCases {
                SnapshotCase(
                    name: scenario.rawValue,
                    configurations: scenario == .otherChannel ? .fullContentScreenRepresentative :
                        SnapshotConfiguration.combinations(
                            devices: [.iPhoneFullContent],
                            colorSchemes: [.light, .dark],
                        ),
                    measurementReadiness: .sameAsCapture,
                ) {
                    InstallerBrowserPreview.navigation(
                        to: .build(scenario.selection),
                        model: scenario.model,
                    )
                }
            }
        }
    }

    #Preview { UpdateBuildView.snapshotPreviews }
#endif
