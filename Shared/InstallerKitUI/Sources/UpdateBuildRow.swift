import InstallerKit
import SFSafeSymbols
import SwiftUI

/// A single accessible navigation action for a channel's latest build or a history entry.
struct UpdateBuildRow: View {
    enum Kind {
        case channel(installed: Bool)
        case release(installed: Bool)
    }

    let selection: UpdateBuildBrowser.Selection
    let release: UpdateCatalog.Release
    let kind: Kind

    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.browser
        NavigationLink(value: UpdateBrowserView.Route.build(selection)) {
            UpdateCard(title: nil) {
                HStack(alignment: .firstTextBaseline, spacing: style.spacing) {
                    VStack(alignment: .leading, spacing: style.spacing) {
                        UpdateBuildHeading(channel: selection.channel, release: release, kind: kind)
                        UpdateBuildMetadata(release: release)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemSymbol: .chevronRight)
                        .font(style.arrowFont)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.primary)
                .frame(minHeight: style.minimumHeight)
                .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: .installerViewBuild))
    }
}

private struct UpdateBuildHeading: View {
    let channel: InstalledBuild.Channel
    let release: UpdateCatalog.Release
    let kind: UpdateBuildRow.Kind
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        switch kind {
            case let .channel(installed):
                UpdateChannelTitle(channel: channel, pullRequestTitle: release.pullRequestTitle)
                if installed {
                    badge(.installerInstalledChannel)
                }
                UpdateBuildVersion(version: release.buildDetails?.version)
                    .font(stylesheet.browser.metadataFont)
            case let .release(installed):
                UpdateBuildVersion(version: release.buildDetails?.version)
                    .font(stylesheet.browser.titleFont)
                if installed {
                    badge(.installerInstalled)
                }
        }
    }

    private func badge(_ title: LocalizedStringResource) -> some View {
        Label(String(localized: title), systemSymbol: .checkmarkCircleFill)
            .font(stylesheet.browser.badgeFont)
            .foregroundStyle(.tint)
    }
}

private struct UpdateChannelTitle: View {
    let channel: InstalledBuild.Channel
    let pullRequestTitle: String?
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        Text(verbatim: channel.rawValue.uppercased())
            .font(stylesheet.browser.titleFont)
        if let title = pullRequestTitle {
            Text(verbatim: title)
                .font(stylesheet.browser.titleFont)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UpdateBuildVersion: View {
    let version: String?

    var body: some View {
        if let version {
            Text(.installerVersionNumber(version))
        } else {
            Text(.installerVersionNotRecorded)
        }
    }
}

private struct UpdateBuildMetadata: View {
    let release: UpdateCatalog.Release
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        Text(.installerBuildNumber("\(release.id.run).\(release.id.attempt)"))
            .font(stylesheet.browser.metadataFont)
        Text(release.publishedAt, format: .dateTime.month(.abbreviated).day().year())
            .font(stylesheet.browser.metadataFont)
            .foregroundStyle(.secondary)
        Text(verbatim: String(release.sha.rawValue.prefix(stylesheet.browser.revisionLength)))
            .font(stylesheet.browser.revisionFont)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview { UpdateBrowserView.snapshotPreviews }
#endif
