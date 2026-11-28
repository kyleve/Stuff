import InstallerKit
import SFSafeSymbols
import SwiftUI

struct UpdateChangeLink: View {
    let commit: UpdateCatalog.Commit
    let url: URL
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.changes
        Link(destination: url) {
            HStack(alignment: .firstTextBaseline, spacing: style.spacing) {
                VStack(alignment: .leading, spacing: style.spacing) {
                    Text(verbatim: commit.subject)
                        .font(style.titleFont)
                        .foregroundStyle(.primary)
                    Text(verbatim: String(commit.sha.rawValue.prefix(style.revisionLength)))
                        .font(style.revisionFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemSymbol: .arrowUpRight)
                    .font(style.arrowFont)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: style.minimumHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: .installerOpenCommit))
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
