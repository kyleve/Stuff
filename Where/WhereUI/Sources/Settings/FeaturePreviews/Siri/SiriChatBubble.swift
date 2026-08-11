import SFSafeSymbols
import SwiftUI

/// One side of the compact example conversation used to explain an App Intent.
struct SiriChatBubble: View {
    enum Speaker {
        case user
        case siri
    }

    let speaker: Speaker
    let text: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        let brand = stylesheet.palette.brand
        HStack(alignment: .bottom, spacing: stylesheet.spacing.small) {
            if speaker == .user {
                Spacer(minLength: style.siri.bubble.indent)
            } else {
                speakerIcon
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(speaker == .user ? brand.onMidnight : brand.ink)
                .padding(.horizontal, style.siri.bubble.horizontalPadding)
                .padding(.vertical, style.siri.bubble.verticalPadding)
                .background(
                    speaker == .user ? brand.midnight : brand.canvas,
                    in: .rect(cornerRadius: style.siri.bubble.cornerRadius),
                )

            if speaker == .siri {
                Spacer(minLength: style.siri.bubble.indent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var speakerIcon: some View {
        let style = stylesheet.featureDiscovery
        return Image(systemSymbol: .waveform)
            .font(.system(size: style.siri.speakerIcon.symbolPointSize, weight: .bold))
            .foregroundStyle(stylesheet.palette.brand.onMidnight)
            .frame(
                width: style.siri.speakerIcon.containerSize,
                height: style.siri.speakerIcon.containerSize,
            )
            .background(stylesheet.palette.brand.midnight, in: .circle)
            .overlay {
                Circle()
                    .stroke(style.siri.accent.opacity(0.6), lineWidth: 0.75)
            }
            .fixedSize()
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        VStack {
            SiriChatBubble(
                speaker: .user,
                text: String(localized: .settingsExploreSiriTodayRequest),
            )
            SiriChatBubble(
                speaker: .siri,
                text: String(localized: .settingsExploreSiriTodayResponse),
            )
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
