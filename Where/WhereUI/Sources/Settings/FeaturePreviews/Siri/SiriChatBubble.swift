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
        HStack(alignment: .bottom, spacing: stylesheet.spacing.small) {
            if speaker == .user {
                Spacer(minLength: style.siri.bubble.indent)
            } else {
                speakerIcon
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(speaker == .user ? Color.white : Color.primary)
                .padding(.horizontal, style.siri.bubble.horizontalPadding)
                .padding(.vertical, style.siri.bubble.verticalPadding)
                .background(
                    speaker == .user ? style.siri.accent : Color(.tertiarySystemFill),
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
        return Image(systemName: "waveform")
            .font(.system(size: style.siri.speakerIcon.symbolPointSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(
                width: style.siri.speakerIcon.containerSize,
                height: style.siri.speakerIcon.containerSize,
            )
            .background(style.siri.accent.gradient, in: .circle)
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
