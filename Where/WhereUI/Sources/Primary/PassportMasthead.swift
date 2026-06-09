import SwiftUI

/// The app wordmark embossed in gold foil that catches a moving specular
/// glint as the device tilts, like the gilt title on a passport cover. Falls
/// back to a fixed, gentle highlight under Reduce Motion or on hardware
/// without device motion.
struct PassportMasthead: View {
    let title: String
    var tilt: TiltProvider?

    var body: some View {
        Text(verbatim: title.uppercased())
            .font(.system(
                size: UIConstants.Size.mastheadFontSize,
                weight: .heavy,
                design: .serif,
            ))
            .tracking(2)
            .goldFoil(tilt: tilt)
            .shadow(
                color: .black.opacity(0.45),
                radius: UIConstants.Spacings.xSmall,
                y: UIConstants.Spacings.xxSmall,
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)
    }
}

#if DEBUG
    #Preview {
        ZStack {
            Color.black.ignoresSafeArea()
            PassportMasthead(title: "Where")
                .padding()
        }
    }
#endif
