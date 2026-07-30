#if DEBUG
    import SwiftUI

    /// The floating developer launcher.
    ///
    /// A semantic button so VoiceOver and Voice Control receive the same
    /// interaction as touch users. Its wrench becomes a close glyph while the
    /// accordion is open; dragging remains owned by ``DeveloperOverlay``.
    ///
    /// It sizes itself — the diameter scales with Dynamic Type via `@ScaledMetric`
    /// — so the number lives here once rather than being duplicated at the call
    /// site; the overlay measures the rendered size for its drag math.
    struct DeveloperOverlayButton: View {
        let isMenuPresented: Bool
        let action: () -> Void

        @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 52

        var body: some View {
            Button(action: action) {
                Image(systemName: isMenuPresented ? "xmark" : "wrench.and.screwdriver")
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: diameter, height: diameter)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .accessibilityLabel(
                isMenuPresented
                    ? String(localized: .developerMenuClose)
                    : String(localized: .developerButtonLabel),
            )
        }
    }

    #Preview("Light") {
        ZStack {
            LinearGradient(
                colors: [.teal, .orange, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .ignoresSafeArea()

            DeveloperOverlayButton(isMenuPresented: false, action: {})
        }
        .environment(\.colorScheme, .light)
    }

    #Preview("Dark") {
        ZStack {
            LinearGradient(
                colors: [.teal, .orange, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .ignoresSafeArea()

            DeveloperOverlayButton(isMenuPresented: true, action: {})
        }
        .environment(\.colorScheme, .dark)
    }
#endif
