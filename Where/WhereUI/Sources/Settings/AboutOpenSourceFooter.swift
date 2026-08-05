import Foundation
import SwiftUI

/// A compact passport-style sign-off linking the About screen to Where's source.
struct AboutOpenSourceFooter: View {
    static let projectURL = URL(string: "https://github.com/kyleve/Stuff")!

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.AboutOpenSourceStyle {
        stylesheet.aboutOpenSource
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius)
    }

    var body: some View {
        Link(destination: Self.projectURL) {
            HStack(spacing: style.contentSpacing) {
                sourceSeal

                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(String(localized: .settingsAboutSourceTitle))
                        .font(style.titleFont)
                        .foregroundStyle(.primary)
                    Text(String(localized: .settingsAboutSourceAction))
                        .font(style.actionFont)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let rosette = style.rosette
                SecurityPrintRosette(
                    tint: .accentColor,
                    wobble: rosette.wobble,
                    lineWidth: rosette.lineWidth,
                    primaryRingSpacing: rosette.primaryRingSpacing,
                    secondaryRingSpacing: rosette.secondaryRingSpacing,
                    primaryOpacity: rosette.primaryOpacity,
                    secondaryOpacity: rosette.secondaryOpacity,
                )
            }
            .glassEffect(
                .regular.tint(Color.accentColor.opacity(style.glassTintOpacity))
                    .interactive(),
                in: shape,
            )
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var sourceSeal: some View {
        let seal = style.seal
        return ZStack {
            Circle()
                .strokeBorder(.tint, lineWidth: seal.outerLineWidth)
            Circle()
                .strokeBorder(
                    .tint.opacity(0.65),
                    style: StrokeStyle(
                        lineWidth: seal.innerLineWidth,
                        dash: [seal.dashLength, seal.dashSpacing],
                    ),
                )
                .padding(seal.innerInset)
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(seal.symbolFont)
                .foregroundStyle(.tint)
        }
        .frame(width: seal.size, height: seal.size)
        .rotationEffect(.degrees(seal.rotationDegrees))
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        Form {
            AboutOpenSourceFooter()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .whereBroadwayRoot()
    }
#endif
