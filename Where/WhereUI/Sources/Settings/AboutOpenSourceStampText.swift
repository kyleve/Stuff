import SwiftUI

/// Keeps the source stamp's title and action together across adaptive layouts.
struct AboutOpenSourceStampText: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.openSourceStamp
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(LocalizedStringResource.settingsAboutSourceTitle)
                .font(style.titleFont)
                .bold()
                .foregroundStyle(style.tint.opacity(style.ink.titleOpacity))
            Text(LocalizedStringResource.settingsAboutSourceAction)
                .font(style.detailFont)
                .foregroundStyle(style.tint.opacity(style.ink.detailOpacity))
        }
    }
}

#if DEBUG
    #Preview {
        AboutOpenSourceStampText()
            .padding()
            .whereBroadwayRoot()
    }
#endif
