#if DEBUG
    import SwiftUI

    /// The collapsed, floating developer entry point.
    ///
    /// Kept as its own view (with no behavior of its own) so the look can be
    /// swapped later without touching the overlay's drag / presentation logic in
    /// ``DeveloperOverlay``. Deliberately understated: an outlined ring around a
    /// wrench glyph, no filled background, so it stays out of the way over the
    /// app. A faint shadow keeps the outline legible over light, dark, and busy
    /// backgrounds, and `contentShape` keeps the whole disc tappable despite the
    /// empty center.
    ///
    /// It sizes itself — the diameter scales with Dynamic Type via `@ScaledMetric`
    /// — so the number lives here once rather than being duplicated at the call
    /// site; the overlay measures the rendered size for its drag math.
    struct DeveloperOverlayButton: View {
        @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 52

        var body: some View {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1.5))
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .accessibilityLabel(String(localized: .developerButtonLabel))
                .accessibilityAddTraits(.isButton)
        }
    }

    #Preview {
        // Over a gradient to confirm the outline reads on varied backgrounds.
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
