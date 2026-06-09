import SwiftUI

/// The brushed-gold "gilt" treatment shared by the passport chrome — the
/// masthead wordmark, the crest, and the booklet cover. Centralized so every
/// gilded element catches the same metal and the same moving glint.
enum GoldFoil {
    /// Brushed-gold gradient that reads as embossed gilt on a dark cover.
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.93, blue: 0.7),
                Color(red: 0.86, green: 0.66, blue: 0.32),
                Color(red: 1.0, green: 0.9, blue: 0.66),
                Color(red: 0.72, green: 0.52, blue: 0.24),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }
}

/// Renders the modified view in gold foil with a specular glint that slides
/// laterally as the device tilts — embossed gilt catching the light. Falls
/// back to a fixed, gentle highlight under Reduce Motion or on hardware
/// without device motion.
struct GoldFoilGlint: ViewModifier {
    var tilt: TiltProvider?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lateral position of the glint, normalized `-1...1`. Pinned to a gentle
    /// off-center value when motion is unavailable or reduced.
    private var glintRoll: Double {
        guard !reduceMotion, let roll = tilt?.roll else { return 0.2 }
        return min(1, max(-1, roll))
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(GoldFoil.gradient)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.95), .clear],
                    startPoint: UnitPoint(x: glintRoll * 0.5 - 0.1, y: 0),
                    endPoint: UnitPoint(x: glintRoll * 0.5 + 0.6, y: 1),
                )
                .blendMode(.plusLighter)
            }
            .mask { content }
    }
}

extension View {
    /// Style this view as embossed gold foil whose glint tracks the device's
    /// tilt. Pass `nil` for a fixed highlight (previews, static chrome).
    func goldFoil(tilt: TiltProvider?) -> some View {
        modifier(GoldFoilGlint(tilt: tilt))
    }
}

#if DEBUG
    #Preview {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(verbatim: "WHERE")
                .font(.system(size: 52, weight: .heavy, design: .serif))
                .tracking(2)
                .goldFoil(tilt: nil)
        }
    }
#endif
