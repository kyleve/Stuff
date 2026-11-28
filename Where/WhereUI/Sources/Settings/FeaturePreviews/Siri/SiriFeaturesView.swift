import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// A visual catalog of every user-facing App Intent Where ships to Siri and
/// Shortcuts, plus the tracked-region results it indexes into Spotlight.
struct SiriFeaturesView: View {
    let focus: SettingsFocus?
    let presentation: FeatureDiscoveryPresentation

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                SiriFeaturesContent(presentation: presentation)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension SiriFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .siri
    }

    enum Item: SettingsItem {
        case todayRegions
        case daysInRegion
        case regionOnDate
        case logDay
        case logTrip
        case spotlight

        var title: String {
            switch self {
                case .todayRegions: String(localized: .settingsExploreSiriTodayTitle)
                case .daysInRegion: String(localized: .settingsExploreSiriDaysTitle)
                case .regionOnDate: String(localized: .settingsExploreSiriDateTitle)
                case .logDay: String(localized: .settingsExploreSiriLogDayTitle)
                case .logTrip: String(localized: .settingsExploreSiriLogTripTitle)
                case .spotlight: String(localized: .settingsExploreSpotlightTitle)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsSiri))
        }
    }
}

#if DEBUG
    extension SiriFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                SiriFeaturesView(
                    focus: nil,
                    presentation: PreviewSupport.featureDiscoveryPresentation(),
                )
            }
        }
    }

    #Preview {
        NavigationStack {
            SiriFeaturesView(
                focus: nil,
                presentation: PreviewSupport.featureDiscoveryPresentation(),
            )
        }
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension SiriFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            SiriFeaturesView.self,
            title: "Siri, Shortcuts & Spotlight",
        )
    }
#endif

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
private struct SiriFeaturesContent: View {
    let presentation: FeatureDiscoveryPresentation

    var body: some View {
        Form {
            FeatureMarketingHeaderRow(
                title: String(localized: .settingsExploreSiriTitle),
                tagline: .settingsExploreSiriTagline,
                destination: .siri,
            )

            SiriIntentExamplesSection(presentation: presentation)

            SiriSpotlightSection(example: presentation.spotlightExample)
        }
        .whereFormRoot()
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
    }
}

private struct SiriIntentExamplesSection: View {
    let presentation: FeatureDiscoveryPresentation

    var body: some View {
        Section {
            ForEach(
                SiriIntentFeature.allCases.enumerated(),
                id: \.element,
            ) { index, feature in
                SiriIntentExampleRow(feature: feature, index: index, presentation: presentation)
            }
        } footer: {
            Text(String(localized: .settingsExploreSiriFooter))
                .staggeredReveal(order: SiriIntentFeature.allCases.count + 1)
        }
    }
}

private struct SiriSpotlightSection: View {
    let example: FeatureDiscoveryPresentation.SpotlightExample

    var body: some View {
        Section {
            FeatureSpotlightPreview(example: example)
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
                .settingsRow(SiriFeaturesView.Item.spotlight, restingBackground: .clear)
                .staggeredReveal(order: SiriIntentFeature.allCases.count + 1)
        } footer: {
            FeatureMarketingFooter(
                detail: .settingsExploreSpotlightFooter,
                order: SiriIntentFeature.allCases.count + 2,
            )
        }
    }
}

#if DEBUG
    #Preview("Siri Features Content") {
        NavigationStack { SiriFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif

/// A miniature Spotlight result showing how an indexed tracked region opens
/// its Where day-count query.
private struct FeatureSpotlightPreview: View {
    let example: FeatureDiscoveryPresentation.SpotlightExample

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: style.contentSpacing) {
                Label(
                    String(localized: .settingsExploreSpotlightTitle),
                    systemSymbol: .magnifyingglass,
                )
                .font(.headline)

                SpotlightQueryField(query: example.query)

                SpotlightResultRow(example: example)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: .settingsExploreSpotlightPreviewLabel(
            example.query,
            example.resultTitle,
            example.resultSubtitle,
        )))
    }
}

private struct SpotlightQueryField: View {
    let query: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Label {
            Text(query)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, stylesheet.spacing.medium)
        .padding(.vertical, stylesheet.spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .capsule)
    }
}

private struct SpotlightResultRow: View {
    let example: FeatureDiscoveryPresentation.SpotlightExample

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.medium) {
            AppIconImage(name: "AppIconClassic", size: 44)

            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(example.resultTitle)
                    .font(.headline)
                Text(example.resultSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: stylesheet.spacing.small)

            Image(systemSymbol: .chevronRight)
                .font(.subheadline.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
    #Preview("Feature Spotlight Preview") {
        FeatureSpotlightPreview(
            example: .init(
                query: "California",
                resultTitle: "Days in California",
                resultSubtitle: "132 days in 2026",
            ),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif

private struct SiriIntentExampleRow: View {
    let feature: SiriIntentFeature
    let index: Int
    let presentation: FeatureDiscoveryPresentation

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        let personalized = presentation.siriExample(for: feature)
        SiriIntentCard(
            title: feature.item.title,
            systemSymbol: feature.systemSymbol,
            request: personalized?.request ?? feature.request,
            response: personalized?.response ?? feature.response,
        )
        .listRowBackground(Color.clear)
        .listRowInsets(.init(
            top: style.siri.card.rowVerticalInset,
            leading: 0,
            bottom: style.siri.card.rowVerticalInset,
            trailing: 0,
        ))
        .listRowSeparator(.hidden)
        .settingsRow(feature.item, restingBackground: .clear)
        .staggeredReveal(order: index + 1)
    }
}

#if DEBUG
    #Preview("Siri Intent Example Row") {
        NavigationStack { SiriFeaturesView.snapshotPreviews }.whereBroadwayRoot()
    }
#endif

/// A discoverability card that demonstrates one intent as a two-message Siri
/// conversation without invoking the intent or reading the user's data.
private struct SiriIntentCard: View {
    let title: String
    let systemSymbol: SFSymbol
    let request: String
    let response: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(alignment: .leading, spacing: style.siri.card.spacing) {
            SiriIntentHeading(title: title, systemSymbol: systemSymbol)
            SiriChatBubble(speaker: .user, text: request)
            SiriChatBubble(speaker: .siri, text: response)
        }
        .padding(style.siri.card.padding)
        .frame(maxWidth: style.siri.card.maxWidth, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: .rect(cornerRadius: style.siri.card.cornerRadius),
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: .settingsExploreSiriCardAccessibilityLabel(title)))
        .accessibilityValue(String(localized: .settingsExploreSiriCardAccessibilityValue(
            request,
            response,
        )))
    }
}

private struct SiriIntentHeading: View {
    let title: String
    let systemSymbol: SFSymbol

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemSymbol: systemSymbol)
                .foregroundStyle(stylesheet.featureDiscovery.siri.accent)
        }
        .font(.headline)
    }
}

#if DEBUG
    #Preview("Siri Intent Card") {
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

/// One side of the compact example conversation used to explain an App Intent.
private struct SiriChatBubble: View {
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
                SiriSpeakerIcon()
            }

            SiriChatMessage(speaker: speaker, text: text)

            if speaker == .siri {
                Spacer(minLength: style.siri.bubble.indent)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SiriSpeakerIcon: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        Image(systemSymbol: .waveform)
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

private struct SiriChatMessage: View {
    let speaker: SiriChatBubble.Speaker
    let text: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        Text(text)
            .font(.subheadline)
            .foregroundStyle(speaker == .user ? Color.white : Color.primary)
            .padding(.horizontal, style.siri.bubble.horizontalPadding)
            .padding(.vertical, style.siri.bubble.verticalPadding)
            .background(
                speaker == .user ? style.siri.accent : Color(.tertiarySystemFill),
                in: .rect(cornerRadius: style.siri.bubble.cornerRadius),
            )
    }
}

#if DEBUG
    #Preview("Siri Chat Bubble") {
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
