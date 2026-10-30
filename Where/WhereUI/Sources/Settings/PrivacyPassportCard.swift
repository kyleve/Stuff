import BroadwayUI
import SwiftUI

/// Reassures the reader that Where's location history stays in their Apple storage.
struct PrivacyPassportCard: View {
    let presentation: PrivacyPassportPresentation
    let disclosureInteraction: PrivacyPassportDisclosureInteraction
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        PrivacyPassportDarkCard(
            presentation: presentation,
            disclosureInteraction: disclosureInteraction,
            ambientShadow: ambientShadow,
        )
        .environment(\.colorScheme, .dark)
        .bMode(.dark)
    }

    private var ambientShadow: WhereStylesheet.MatteSurface.Shadow? {
        if case let .matte(paper) = stylesheet.privacyPassportCard.surface { paper.shadow }
        else { nil }
    }
}

/// Resolves layout, typography, and reflection policy in the same mode as the paper.
private struct PrivacyPassportDarkCard: View {
    let presentation: PrivacyPassportPresentation
    let disclosureInteraction: PrivacyPassportDisclosureInteraction
    let ambientShadow: WhereStylesheet.MatteSurface.Shadow?
    @State private var tilt = TiltProvider()

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.whereComponentStylesheet) private var components

    var body: some View {
        let style = stylesheet.privacyPassportCard
        PrivacyPassportCardSurface(tilt: tilt, content: {
            VStack(alignment: .leading, spacing: style.sectionSpacing) {
                PrivacyPassportHeader()

                Text(presentation.locationDetail)
                    .font(components[.privacy].body ?? style.detailFont)
                    .foregroundStyle(.whereSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: style.disclosure.rowSpacing) {
                    ForEach(presentation.disclosures) { disclosure in
                        PrivacyPassportDisclosureRow(
                            disclosure: disclosure,
                            interaction: disclosureInteraction,
                        )
                    }
                }
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }, ambientShadowOverride: ambientShadow)
            .observesTilt(tilt, enabled: style.surface.usesReflection)
            .whereThemeArtworkSpace(.privacy)
    }
}

#if DEBUG
    #Preview {
        Form {
            PrivacyPassportCard(presentation: PrivacyPassportPresentation(
                configuration: .defaults(isDebugBuild: false),
            ), disclosureInteraction: .linkToSettings)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    import SnapshotKit

    extension PrivacyPassportCard: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereThemeSnapshot(name: "Privacy", configurations: .componentRepresentative) {
                PrivacyPassportCard(
                    presentation: PrivacyPassportPresentation(
                        configuration: .defaults(isDebugBuild: false),
                    ),
                    disclosureInteraction: .linkToSettings,
                )
                .padding(24)
                .background(.background)
            }
        }
    }

    #Preview("Themes") {
        PrivacyPassportCard.snapshotPreviews
    }
#endif
