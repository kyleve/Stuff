import SwiftUI

/// The "cover" of the Where passport: a deep navy card with a gold emblem,
/// serif wordmark, the selected year, and the days logged so far — finished
/// with a gold holographic sheen that catches the light as the device tilts.
struct PassportCoverHeader: View {
    let year: Int
    let trackedDayCount: Int
    var tilt: TiltProvider

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.card, style: .continuous)
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacings.large) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: UIConstants.Size.passportEmblemSize))
                .foregroundStyle(Self.gold.gradient)
                .accessibilityHidden(true)

            VStack(spacing: UIConstants.Spacings.xxSmall) {
                Text(Strings.primaryTitle)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .tracking(4)
                Text(Strings.passportCoverSubtitle)
                    .font(.system(.subheadline, design: .serif))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Self.gold.opacity(0.8))
            }

            Rectangle()
                .fill(Self.gold.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, UIConstants.Spacings.xxxLarge)

            Text(year.formatted(.number.grouping(.never)))
                .font(.system(
                    size: UIConstants.Size.heroNumberFontSize,
                    weight: .heavy,
                    design: .serif,
                ))
                .contentTransition(.numericText())
            Text(Strings.primaryHeaderSubtitle(count: trackedDayCount))
                .font(.footnote)
                .foregroundStyle(Self.gold.opacity(0.75))
        }
        .foregroundStyle(Self.gold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, UIConstants.Spacings.xxxLarge)
        .padding(.horizontal, UIConstants.Padding.card)
        .background(Self.coverGradient, in: shape)
        .overlay {
            shape.strokeBorder(Self.gold.opacity(0.5), lineWidth: 1.5)
        }
        .holographicSheen(roll: tilt.roll, pitch: tilt.pitch, in: shape, tint: Self.gold)
        .clipShape(shape)
        .accessibilityElement(children: .combine)
    }

    /// Embossed-gold foil color used throughout the cover.
    private static let gold = Color(red: 0.83, green: 0.69, blue: 0.36)

    private static let coverGradient = LinearGradient(
        colors: [
            Color(red: 0.11, green: 0.13, blue: 0.30),
            Color(red: 0.05, green: 0.06, blue: 0.16),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing,
    )
}

#if DEBUG
    #Preview {
        PassportCoverHeader(year: 2026, trackedDayCount: 148, tilt: .preview)
            .padding()
    }
#endif
