#if DEBUG
    import SwiftUI

    /// The collapsed, floating developer entry point.
    ///
    /// Kept as its own view (with no behavior of its own) so the look can be
    /// swapped later without touching the overlay's drag / presentation logic in
    /// ``DeveloperOverlay``. It's a solid disc with a white glyph, ring, and
    /// shadow so it stays legible over light, dark, and busy photo backgrounds.
    ///
    /// It sizes itself — the diameter scales with Dynamic Type via `@ScaledMetric`
    /// — so the number lives here once rather than being duplicated at the call
    /// site; the overlay measures the rendered size for its drag math.
    struct DeveloperOverlayButton: View {
        @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 52

        var body: some View {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: diameter * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.indigo.gradient))
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
                .accessibilityLabel(Strings.developerButtonLabel)
                .accessibilityAddTraits(.isButton)
        }
    }

    #Preview {
        // Over a gradient to confirm the disc reads on varied backgrounds.
        ZStack {
            LinearGradient(
                colors: [.teal, .orange, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .ignoresSafeArea()

            DeveloperOverlayButton()
        }
    }
#endif
