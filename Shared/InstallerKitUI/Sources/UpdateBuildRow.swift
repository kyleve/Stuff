import InstallerKit
import SFSafeSymbols
import SwiftUI

/// A single accessible navigation action for a channel's latest build or a history entry.
struct UpdateBuildRow: View {
    enum Kind {
        case channel(InstalledBuild.Channel, installed: Bool)
        case release(installed: Bool)
    }

    let release: UpdateCatalog.Release
    let kind: Kind
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.browser
        HStack(alignment: .firstTextBaseline, spacing: style.spacing) {
            VStack(alignment: .leading, spacing: style.spacing) {
                switch kind {
                    case let .channel(channel, installed):
                        Text(verbatim: channel.rawValue.uppercased())
                            .font(style.titleFont)
                        if let title = release.pullRequestTitle {
                            Text(verbatim: title)
                                .font(style.titleFont)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if installed { badge(.installerInstalledChannel) }
                        version.font(style.metadataFont)
                    case let .release(installed):
                        version.font(style.titleFont)
                        if installed { badge(.installerInstalled) }
                }
                Text(.installerBuildNumber("\(release.id.run).\(release.id.attempt)"))
                    .font(style.metadataFont)
                Text(release.publishedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(style.metadataFont)
                    .foregroundStyle(.secondary)
                Text(verbatim: String(release.sha.rawValue.prefix(style.revisionLength)))
                    .font(style.revisionFont)
                    .foregroundStyle(.secondary)
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

    @ViewBuilder private var version: some View {
        if let version = release.buildDetails?.version {
            Text(.installerVersionNumber(version))
        } else {
            Text(.installerVersionNotRecorded)
        }
    }

    private func badge(_ title: LocalizedStringResource) -> some View {
        Label(String(localized: title), systemSymbol: .checkmarkCircleFill)
            .font(stylesheet.browser.badgeFont)
            .foregroundStyle(.tint)
    }
}

#if DEBUG
    #Preview { UpdateBrowserView.snapshotPreviews }
#endif
