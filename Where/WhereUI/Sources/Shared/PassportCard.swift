import SwiftUI

/// The shared card content and chrome used for Where's passport statements.
struct PassportCard: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let sealSystemImage: String
    let accessorySystemImage: String?
    let isInteractive: Bool
    /// A live provider selects the reflective white privacy surface; `nil`
    /// keeps the security-print surface used by the GitHub card.
    let tilt: TiltProvider?

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.PassportCardStyle {
        stylesheet.passportCard
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius)
    }

    var body: some View {
        PassportCardSurface(
            tilt: tilt,
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
        .clipShape(shape)
        .contentShape(shape)
        .shadow(
            color: Color.accentColor.opacity(style.accentGlow.opacity),
            radius: style.accentGlow.radius,
            y: style.accentGlow.offsetY,
        )
        .shadow(
            color: Color.black.opacity(style.liftShadow.opacity),
            radius: style.liftShadow.radius,
            y: style.liftShadow.offsetY,
        )
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
            tilt: .preview,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
