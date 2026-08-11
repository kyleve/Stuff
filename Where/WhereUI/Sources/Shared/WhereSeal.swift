import SwiftUI

/// Where's compact house mark: a serif W held inside a cartographic globe.
///
/// The seal is deliberately built from native vectors so it remains crisp from
/// a lock-screen widget to the annual ledger cover. It is always ornamental;
/// the surrounding card or heading owns the accessible name and meaning.
struct WhereSeal: View {
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let style = stylesheet.seal

            ZStack {
                Circle()
                    .stroke(tint, lineWidth: style.outerRingWidth)

                Circle()
                    .stroke(tint.opacity(0.7), lineWidth: style.innerRingWidth)
                    .padding(style.innerRingInset)

                Ellipse()
                    .stroke(
                        tint.opacity(style.meridianOpacity),
                        lineWidth: style.meridianWidth,
                    )
                    .frame(width: size * 0.36, height: size - style.innerRingInset * 2)

                Ellipse()
                    .stroke(
                        tint.opacity(style.meridianOpacity),
                        lineWidth: style.meridianWidth,
                    )
                    .frame(width: size - style.innerRingInset * 2, height: size * 0.34)

                Text(verbatim: "W")
                    .font(.system(
                        size: size * style.letterScale,
                        weight: .semibold,
                        design: .serif,
                    ))
                    .foregroundStyle(tint)
                    .offset(y: -size * 0.01)

                Rectangle()
                    .fill(tint)
                    .frame(
                        width: size * style.waypointScale,
                        height: size * style.waypointScale,
                    )
                    .rotationEffect(.degrees(45))
                    .offset(
                        x: size * style.waypointOffset.width,
                        y: size * style.waypointOffset.height,
                    )
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        HStack(spacing: 32) {
            WhereSeal(tint: WhereStylesheet.default.palette.brand.midnight)
                .frame(width: 104)

            WhereSeal(tint: WhereStylesheet.default.palette.brand.brass)
                .frame(width: 72)
                .padding(18)
                .background(WhereStylesheet.default.palette.brand.midnight)
        }
        .padding()
        .background(WhereStylesheet.default.palette.brand.canvas)
        .whereBroadwayRoot()
    }
#endif
