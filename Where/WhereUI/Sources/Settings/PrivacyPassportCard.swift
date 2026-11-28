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

                PrivacyPassportDisclosureList(
                    presentation: presentation,
                    interaction: disclosureInteraction,
                    rowSpacing: style.disclosure.rowSpacing,
                )
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .observesTilt(tilt, enabled: style.surface.usesReflection)
    }
}

private struct PrivacyPassportDisclosureList: View {
    let presentation: PrivacyPassportPresentation
    let interaction: PrivacyPassportDisclosureInteraction
    let rowSpacing: CGFloat

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(presentation.disclosures) { disclosure in
                PrivacyPassportDisclosureRow(
                    disclosure: disclosure,
                    interaction: interaction,
                )
            }
        }
    }
}

#if DEBUG
    #Preview { PrivacyPassportCardPreview() }

    private struct PrivacyPassportCardPreview: View {
        var body: some View {
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
    }
#endif

#if DEBUG
    import SnapshotKit

    extension PrivacyPassportCard: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            // Supplied disclosure content determines height; tilt only affects the
            // surface. Final settling still verifies the rendered card.
            whereThemeSnapshot(
                name: "Privacy",
                configurations: .componentRepresentative,
                measurementReadiness: .immediate,
            ) {
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

/// Restacks the privacy seal above its title when accessibility text needs the width.
private struct PrivacyPassportHeader: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard
        layout {
            PassportSeal(systemSymbol: .lockShieldFill, tint: style.reflectiveSurface.accent)
            Text(LocalizedStringResource.settingsPrivacyTitle)
                .font(style.titleFont)
                .bold()
                .foregroundStyle(.primary)
        }
    }

    private var layout: AnyLayout {
        let style = stylesheet.privacyPassportCard
        return if style.headerLayout == .stacked {
            AnyLayout(VStackLayout(alignment: .leading, spacing: style.headerSpacing))
        } else {
            AnyLayout(HStackLayout(spacing: style.headerSpacing))
        }
    }
}

#if DEBUG
    #Preview("Header") { PrivacyPassportHeaderPreview() }

    private struct PrivacyPassportHeaderPreview: View {
        var body: some View {
            PrivacyPassportCardSurface(tilt: .preview) {
                PrivacyPassportHeader()
                    .padding()
            }
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif

/// Presents one active privacy-reporting disclosure as a self-contained status row.
private struct PrivacyPassportDisclosureRow: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let interaction: PrivacyPassportDisclosureInteraction

    @Environment(\.isInDemoMode) private var isInDemoMode

    var body: some View {
        if interaction == .linkToSettings, !isInDemoMode {
            NavigationLink(value: SettingsRoute(.privacyDiagnostics)) {
                PrivacyPassportDisclosureRowLabel(
                    disclosure: disclosure,
                    showsSettingsIndicator: true,
                )
            }
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
        } else {
            PrivacyPassportDisclosureRowLabel(
                disclosure: disclosure,
                showsSettingsIndicator: false,
            )
        }
    }
}

#if DEBUG
    #Preview("Disclosure") { PrivacyPassportDisclosureRowPreview() }

    private struct PrivacyPassportDisclosureRowPreview: View {
        var body: some View {
            NavigationStack {
                PrivacyPassportCardSurface(tilt: .preview) {
                    PrivacyPassportDisclosureRow(
                        disclosure: .crashReports,
                        interaction: .linkToSettings,
                    )
                    .padding()
                }
                .padding()
            }
            .whereBroadwayRoot()
        }
    }
#endif
