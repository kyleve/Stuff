import SFSafeSymbols
import SwiftUI

/// The shared card content and chrome used for Where's passport statements.
struct PassportCard: View {
    let title: LocalizedStringResource
    let detail: String
    let sealSystemSymbol: SFSymbol
    let accessorySystemSymbol: SFSymbol?
    let isInteractive: Bool
    let surface: PassportCardSurfaceKind

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.PassportCardStyle {
        stylesheet.passportCard
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius)
    }

    private var glowColor: Color {
        surface.isReflective ? style.reflectiveSurface.backgroundTop : .accentColor
    }

    private var glowOpacity: Double {
        surface.isReflective
            ? style.reflectiveSurface.glowOpacity
            : style.accentGlow.opacity
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
                    Image(systemSymbol: sealSystemSymbol)
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

                if let accessorySystemSymbol {
                    Image(systemSymbol: accessorySystemSymbol)
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
            color: glowColor.opacity(glowOpacity),
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
            detail: String(localized: .settingsPrivacyDetail),
            sealSystemSymbol: .lockShieldFill,
            accessorySystemSymbol: nil,
            isInteractive: false,
            surface: .reflective(tilt: .preview),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
