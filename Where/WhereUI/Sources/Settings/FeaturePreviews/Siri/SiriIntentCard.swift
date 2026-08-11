import SFSafeSymbols
import SwiftUI

/// A discoverability card that demonstrates one intent as a two-message Siri
/// conversation without invoking the intent or reading the user's data.
struct SiriIntentCard: View {
    let title: String
    let systemSymbol: SFSymbol
    let request: String
    let response: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        let brand = stylesheet.palette.brand
        VStack(alignment: .leading, spacing: style.siri.card.spacing) {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemSymbol: systemSymbol)
                    .foregroundStyle(style.siri.accent)
            }
            .font(.system(.headline, design: .serif).weight(.semibold))
            SiriChatBubble(speaker: .user, text: request)
            SiriChatBubble(speaker: .siri, text: response)
        }
        .padding(style.siri.card.padding)
        .frame(maxWidth: style.siri.card.maxWidth, alignment: .leading)
        .background(
            brand.raisedPaper,
            in: .rect(cornerRadius: style.siri.card.cornerRadius),
        )
        .overlay {
            RoundedRectangle(cornerRadius: style.siri.card.cornerRadius)
                .stroke(
                    brand.brass.opacity(style.marketingPanel.borderOpacity),
                    lineWidth: 0.75,
                )
        }
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
            systemSymbol: .locationFill,
            request: String(localized: .settingsExploreSiriTodayRequest),
            response: String(localized: .settingsExploreSiriTodayResponse),
        )
        .padding()
        .background(Color(.systemGroupedBackground))
        .whereBroadwayRoot()
    }
#endif
