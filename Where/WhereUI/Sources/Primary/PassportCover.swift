import SwiftUI

/// The booklet's closed front cover: deep navy leather with an embossed gold
/// frame, crest, and wordmark. Shown briefly over the Primary tab on first
/// appearance, then swung open by `PrimaryView`. Purely decorative.
struct PassportCover: View {
    var tilt: TiltProvider?

    private var coverShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: UIConstants.CornerRadius.passportPage,
            style: .continuous,
        )
    }

    var body: some View {
        ZStack {
            coverShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.11, blue: 0.20),
                            Color(red: 0.04, green: 0.04, blue: 0.09),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .overlay {
                    coverShape
                        .strokeBorder(GoldFoil.solid.opacity(0.55), lineWidth: 1.5)
                }
                .overlay {
                    coverShape
                        .inset(by: UIConstants.Spacings.large)
                        .strokeBorder(GoldFoil.solid.opacity(0.35), lineWidth: 1)
                }

            VStack(spacing: UIConstants.Spacings.xxxLarge) {
                PassportCrest(tilt: tilt)
                Text(verbatim: Strings.primaryTitle.uppercased())
                    .font(.system(
                        size: UIConstants.Size.coverWordmarkFontSize,
                        weight: .heavy,
                        design: .serif,
                    ))
                    .tracking(4)
                    .goldFoil(tilt: tilt)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: UIConstants.Shadow.cardRadiusCompact)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.09).ignoresSafeArea()
            PassportCover()
                .padding()
        }
    }
#endif
