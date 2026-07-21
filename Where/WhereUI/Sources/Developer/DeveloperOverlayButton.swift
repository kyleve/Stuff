#if DEBUG
    import SwiftUI

    /// The collapsed, floating developer entry point.
    ///
    /// Kept as its own view (with no behavior of its own) so the look can be
    /// swapped without touching the overlay's drag / presentation logic in
    /// ``DeveloperOverlay``. A circular Liquid Glass disc around a wrench glyph:
    /// the glass adapts to light/dark (and to whatever's behind it) on its own,
    /// and the glyph uses `.primary` so it stays legible in either appearance. A
    /// faint shadow keeps the disc separated from busy backgrounds; `contentShape`
    /// keeps the whole circle tappable.
    ///
    /// It sizes itself — the diameter scales with Dynamic Type via `@ScaledMetric`
    /// — so the number lives here once rather than being duplicated at the call
    /// site; the overlay measures the rendered size for its drag math.
    struct DeveloperOverlayButton: View {
        @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 52

        var body: some View {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .accessibilityLabel(Strings.developerButtonLabel)
                .accessibilityAddTraits(.isButton)
        }
    }

    #Preview("Light") {
        DeveloperButtonPreview()
            .environment(\.colorScheme, .light)
    }

    #Preview("Dark") {
        DeveloperButtonPreview()
            .environment(\.colorScheme, .dark)
    }

    /// Over a gradient to confirm the glass + glyph read on varied backgrounds.
    private struct DeveloperButtonPreview: View {
        var body: some View {
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
    }
#endif
