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
                Spacer(minLength: style.bubbleIndent)
            } else {
                speakerIcon
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(speaker == .user ? Color.white : Color.primary)
                .padding(.horizontal, style.bubbleHorizontalPadding)
                .padding(.vertical, style.bubbleVerticalPadding)
                .background(
                    speaker == .user ? style.conversationAccent : Color(.tertiarySystemFill),
                    in: .rect(cornerRadius: style.bubbleCornerRadius),
                )

            if speaker == .siri {
                Spacer(minLength: style.bubbleIndent)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let speakerName = switch speaker {
            case .user:
                String(localized: .settingsExploreSiriUserSpeaker)
            case .siri:
                String(localized: .settingsExploreSiriSpeaker)
        }
        return String(localized: .settingsExploreSiriBubbleAccessibility(speakerName, text))
    }

    private var speakerIcon: some View {
        let style = stylesheet.featureDiscovery
        return Image(systemName: "waveform")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: style.speakerIconSize, height: style.speakerIconSize)
            .background(style.conversationAccent.gradient, in: .circle)
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
