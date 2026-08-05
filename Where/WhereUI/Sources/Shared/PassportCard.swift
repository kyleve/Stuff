import SwiftUI

/// The shared card content and chrome used for Where's passport statements.
struct PassportCard: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let sealSystemImage: String
    let accessorySystemImage: String?
    let isInteractive: Bool
    let surface: PassportCardSurfaceKind

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.PassportCardStyle {
        stylesheet.passportCard
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius)
    }

    var body: some View {
        PassportCardSurface(
            surface: surface,
            isInteractive: isInteractive,
            shape: shape,
        ) {
            HStack(spacing: style.contentSpacing) {
                ZStack {
                    Circle()
                        .strokeBorder(.tint, lineWidth: style.seal.outerLineWidth)
                    Circle()
                        .strokeBorder(
                            .tint.opacity(0.65),
                            style: StrokeStyle(
                                lineWidth: style.seal.innerLineWidth,
                                dash: [style.seal.dashLength, style.seal.dashSpacing],
                            ),
                        )
                        .padding(style.seal.innerInset)
                    Image(systemName: sealSystemImage)
                        .font(style.seal.symbolFont)
                        .foregroundStyle(.tint)
                }
                .frame(width: style.seal.size, height: style.seal.size)
                .rotationEffect(.degrees(style.seal.rotationDegrees))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(title)
                        .font(style.titleFont)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(style.detailFont)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let accessorySystemImage {
                    Image(systemName: accessorySystemImage)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(shape)
        // The full-width Form row has no system inset to contain the source
        // card's glow. Preserve that vertical breathing room without narrowing
        // the card or adding a backing surface behind the privacy variant.
        .padding(.vertical, surface.isReflective ? 0 : style.shadowBleed)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        PassportCard(
            title: .settingsPrivacyTitle,
            detail: .settingsPrivacyDetail,
            sealSystemImage: "lock.shield.fill",
            accessorySystemImage: nil,
            isInteractive: false,
            surface: .reflective(tilt: .preview),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
