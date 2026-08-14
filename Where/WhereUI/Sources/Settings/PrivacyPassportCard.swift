import SwiftUI

/// Reassures the reader that Where's location history stays in their Apple storage.
struct PrivacyPassportCard: View {
    let presentation: PrivacyPassportPresentation
    let disclosureInteraction: PrivacyPassportDisclosureInteraction
    @State private var tilt = TiltProvider()

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard
        PrivacyPassportCardSurface(tilt: tilt) {
            VStack(alignment: .leading, spacing: style.sectionSpacing) {
                PrivacyPassportHeader()

                Text(presentation.locationDetail)
                    .font(style.detailFont)
                    .foregroundStyle(.secondary)
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
        }
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
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
