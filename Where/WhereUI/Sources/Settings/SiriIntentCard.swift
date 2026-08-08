import SwiftUI

/// A discoverability card that demonstrates one intent as a two-message Siri
/// conversation without invoking the intent or reading the user's data.
struct SiriIntentCard: View {
    let title: String
    let systemImage: String
    let request: String
    let response: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(alignment: .leading, spacing: style.cardSpacing) {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(style.conversationAccent)
            }
            .font(.headline)
            SiriChatBubble(speaker: .user, text: request)
            SiriChatBubble(speaker: .siri, text: response)
        }
        .padding(style.cardPadding)
        .frame(maxWidth: style.cardMaxWidth, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: style.cardCornerRadius))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
    #Preview {
        SiriIntentCard(
            title: String(localized: .settingsExploreSiriTodayTitle),
            systemImage: "location.fill",
            request: String(localized: .settingsExploreSiriTodayRequest),
            response: String(localized: .settingsExploreSiriTodayResponse),
        )
        .padding()
        .background(Color(.systemGroupedBackground))
        .whereBroadwayRoot()
    }
#endif
