import SwiftUI

struct UpdateNoticeCard: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateCard(title: title) {
            Text(message)
                .font(stylesheet.card.bodyFont)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
