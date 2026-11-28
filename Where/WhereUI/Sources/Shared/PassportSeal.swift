import SFSafeSymbols
import SwiftUI

/// Draws the circular seal shared by Where's Settings passport artwork.
struct PassportSeal: View {
    let systemSymbol: SFSymbol
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.passportSeal
        ZStack {
            Circle()
                .strokeBorder(tint, lineWidth: style.outerLineWidth)
            PassportSealInnerRing(tint: tint)
            Image(systemSymbol: systemSymbol)
                .font(style.symbolFont)
                .foregroundStyle(tint)
        }
        .frame(width: style.size, height: style.size)
        .fixedSize()
        .rotationEffect(.degrees(style.rotationDegrees))
        .accessibilityHidden(true)
    }
}

private struct PassportSealInnerRing: View {
    @Environment(\.stylesheet) private var stylesheet
    let tint: Color

    var body: some View {
        let style = stylesheet.passportSeal
        Circle()
            .strokeBorder(
                tint.opacity(0.65),
                style: StrokeStyle(
                    lineWidth: style.innerLineWidth,
                    dash: [style.dashLength, style.dashSpacing],
                ),
            )
            .padding(style.innerInset)
    }
}

#if DEBUG
    #Preview {
        PassportSeal(systemSymbol: .lockShieldFill, tint: .accentColor)
            .padding()
            .whereBroadwayRoot()
    }
#endif
