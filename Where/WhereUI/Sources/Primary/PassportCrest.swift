import SwiftUI

/// A circular gilt emblem — a double ring around a globe — embossed in the
/// same gold foil as the wordmark, like the coat of arms on a passport cover.
/// Purely decorative; used on the booklet's bio-data page and opening cover.
struct PassportCrest: View {
    var tilt: TiltProvider?
    var size: CGFloat = UIConstants.Size.passportCrest

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(lineWidth: size * 0.035)
            Circle()
                .strokeBorder(
                    style: StrokeStyle(
                        lineWidth: size * 0.015,
                        dash: [size * 0.045, size * 0.035],
                    ),
                )
                .padding(size * 0.09)
            Image(systemName: "globe.americas.fill")
                .font(.system(size: size * 0.42, weight: .medium))
        }
        .frame(width: size, height: size)
        .goldFoil(tilt: tilt)
        .shadow(
            color: .black.opacity(0.45),
            radius: UIConstants.Spacings.xSmall,
            y: UIConstants.Spacings.xxSmall,
        )
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        ZStack {
            Color.black.ignoresSafeArea()
            PassportCrest()
        }
    }
#endif
