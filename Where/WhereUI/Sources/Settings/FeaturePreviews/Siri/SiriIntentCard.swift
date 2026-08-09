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
        VStack(alignment: .leading, spacing: style.siri.card.spacing) {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(style.siri.accent)
            }
            .font(.headline)
            SiriChatBubble(speaker: .user, text: request)
            SiriChatBubble(speaker: .siri, text: response)
        }
        .padding(style.siri.card.padding)
        .frame(maxWidth: style.siri.card.maxWidth, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: style.siri.card.cornerRadius))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: .settingsExploreSiriCardAccessibilityLabel(title)))
        .accessibilityValue(String(localized: .settingsExploreSiriCardAccessibilityValue(
            request,
            response,
        )))
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
