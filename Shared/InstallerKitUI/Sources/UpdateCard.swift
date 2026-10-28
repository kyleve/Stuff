import SwiftUI

/// One shared surface for release notes, metadata, and check controls.
struct UpdateCard<Content: View>: View {
    let title: LocalizedStringResource?
    @ViewBuilder let content: Content
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.card.spacing) {
            if let title {
                Text(title)
                    .font(stylesheet.card.titleFont)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(stylesheet.card.padding)
        .background(
            stylesheet.card.background,
            in: .rect(cornerRadius: stylesheet.card.cornerRadius),
        )
    }
}

#if DEBUG
    #Preview {
        UpdateCard(title: .installerChanges) { Text(.installerNoCommits) }
            .installerBroadwayRoot()
    }
#endif
