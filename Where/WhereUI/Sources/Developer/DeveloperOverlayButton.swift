import SFSafeSymbols
#if DEBUG
    import SwiftUI

    /// The floating developer launcher.
    ///
    /// A semantic button so VoiceOver and Voice Control receive the same
    /// interaction as touch users. Its wrench becomes a close glyph while the
    /// accordion is open; dragging remains owned by ``DeveloperOverlay``.
    ///
    /// The stylesheet scales its diameter. The overlay measures the rendered
    /// size for its drag bounds.
    struct DeveloperOverlayButton: View {
        let isMenuPresented: Bool
        let action: () -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let style = stylesheet.developerOverlay.launcher
            Button(action: action) {
                Image(systemSymbol: isMenuPresented ? .xmark : .wrenchAndScrewdriver)
                    .font(.system(size: style.diameter * style.glyphRatio, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: style.diameter, height: style.diameter)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
            .shadow(color: style.shadowColor, radius: style.shadowRadius, y: style.shadowOffsetY)
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
        .whereBroadwayRoot()
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
        .whereBroadwayRoot()
        .environment(\.colorScheme, .dark)
    }
#endif
