import SwiftUI
import WhereCore

struct AboutVersionSection: View {
    let buildInfo: BuildInfo

    var body: some View {
        Section {
            LabeledContent(
                String(localized: .settingsAboutVersionRow),
                value: WhereFormat.aboutValue(buildInfo.version),
            )
            LabeledContent(
                String(localized: .settingsAboutBuildRow),
                value: WhereFormat.aboutValue(buildInfo.build),
            )
            LabeledContent(
                String(localized: .settingsAboutCommitRow),
                value: WhereFormat.aboutCommit(buildInfo.commit),
            )
        } header: {
            Text(String(localized: .settingsAboutVersionHeader))
        } footer: {
            Text(String(localized: .settingsAboutVersionFooter))
        }
        // Selectable so a bug report can carry the exact commit rather than a
        // squinted-at transcription of it.
        .textSelection(.enabled)
        .settingsRow(AboutSettingsView.Item.version)
    }
}

#if DEBUG
    #Preview {
        Form { AboutVersionSection(buildInfo: PreviewSupport.stampedBuildInfo()) }
            .whereBroadwayRoot()
    }
#endif
