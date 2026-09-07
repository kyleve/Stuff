import SFSafeSymbols
import SwiftUI

/// Shared passport-style stamp surface for compact informational banners.
struct StampBanner<Content: View>: View {
    let systemSymbol: SFSymbol
    let style: WhereStylesheet.StampBannerStyle
    let showsAccessory: Bool
    @ViewBuilder let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let ink = style.ink
        let shape = ContainerRelativeShape()
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: style.contentSpacing) {
                    HStack {
                        PassportSeal(
                            systemSymbol: systemSymbol,
                            tint: style.tint.opacity(ink.sealOpacity),
                        )
                        Spacer(minLength: 0)
                        if showsAccessory {
                            Image(systemSymbol: .arrowUpRight)
                                .foregroundStyle(style.tint.opacity(ink.accessoryOpacity))
                                .accessibilityHidden(true)
                        }
                    }
                    content
                }
            } else {
                HStack(spacing: style.contentSpacing) {
                    PassportSeal(
                        systemSymbol: systemSymbol,
                        tint: style.tint.opacity(ink.sealOpacity),
                    )
                    content
                    Spacer(minLength: 0)
                    if showsAccessory {
                        Image(systemSymbol: .arrowUpRight)
                            .foregroundStyle(style.tint.opacity(ink.accessoryOpacity))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            SecurityPrintRosette(
                tint: style.tint,
                wobble: style.rosette.wobble,
                lineWidth: style.rosette.lineWidth,
                primaryRingSpacing: style.rosette.primaryRingSpacing,
                secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                primaryOpacity: ink.primaryRosetteOpacity,
                secondaryOpacity: ink.secondaryRosetteOpacity,
            )
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                style.tint.opacity(ink.outlineOpacity),
                lineWidth: style.outlineWidth,
            )
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        StampBanner(
            systemSymbol: .exclamationmarkTriangleFill,
            style: .plannedStayWarning,
            showsAccessory: false,
        ) {
            Text("Warning banner")
                .foregroundStyle(.orange)
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
