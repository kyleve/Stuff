import SnapshotKit
import SwiftUI

/// Where's principal privacy statement: a restrained midnight passport carrying
/// literal storage claims rather than ornamental archive language.
struct PrivacyPassportCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet
    @State private var tilt = TiltProvider()

    private var style: WhereStylesheet.PassportCardStyle {
        stylesheet.passportCard
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius)
    }

    var body: some View {
        PassportCardSurface(
            surface: .reflective(tilt: tilt),
            isInteractive: false,
            shape: shape,
        ) {
            VStack(alignment: .leading, spacing: stylesheet.spacing.large) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                        Text(String(localized: .settingsPrivacyDocumentLabel))
                            .font(.caption2.weight(.semibold))
                            .tracking(1.8)
                            .foregroundStyle(stylesheet.palette.brand.brass)
                        Text(String(localized: .settingsPrivacyTitle))
                            .font(.system(.title2, design: .serif).weight(.semibold))
                            .foregroundStyle(stylesheet.palette.brand.onMidnight)
                    }
                    Spacer(minLength: stylesheet.spacing.large)
                    WhereSeal(tint: stylesheet.palette.brand.brass)
                        .frame(width: 58)
                }

                Text(String(localized: .settingsPrivacyDetail))
                    .font(.subheadline)
                    .foregroundStyle(stylesheet.palette.brand.onMidnight.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .overlay(stylesheet.palette.brand.brass.opacity(0.3))

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                        privacyClaim(.settingsPrivacyOnDevice, systemImage: "iphone")
                        privacyClaim(.settingsPrivacyPrivateICloud, systemImage: "icloud")
                        privacyClaim(.settingsPrivacyNoServers, systemImage: "server.rack")
                    }
                } else {
                    HStack(spacing: stylesheet.spacing.small) {
                        privacyClaim(.settingsPrivacyOnDevice, systemImage: "iphone")
                        privacyClaim(.settingsPrivacyPrivateICloud, systemImage: "icloud")
                        privacyClaim(.settingsPrivacyNoServers, systemImage: "server.rack")
                    }
                }
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(shape)
        .shadow(
            color: Color.black.opacity(style.liftShadow.opacity),
            radius: style.liftShadow.radius,
            y: style.liftShadow.offsetY,
        )
        .accessibilityElement(children: .combine)
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }

    private func privacyClaim(
        _ title: LocalizedStringResource,
        systemImage: String,
    ) -> some View {
        Label(String(localized: title), systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(stylesheet.palette.brand.onMidnight.opacity(0.86))
            .padding(.horizontal, stylesheet.spacing.medium)
            .padding(.vertical, stylesheet.spacing.small)
            .background(stylesheet.palette.brand.onMidnight.opacity(0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(stylesheet.palette.brand.brass.opacity(0.22), lineWidth: 0.5)
            }
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
    extension PrivacyPassportCard: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults + [
                    SnapshotConfiguration(
                        layoutDirection: .rightToLeft,
                        device: .iPhoneFullContent,
                    ),
                ],
            ) {
                Form {
                    PrivacyPassportCard()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
    }

    #Preview {
        PrivacyPassportCard.snapshotPreviews
    }
#endif
