import RegionKit
import SwiftUI
import UIKit

/// The modal scrim and adaptive placement for a Locations welcome card.
struct LocationWelcomeOverlay: View {
    let presentation: LocationWelcomeModel.Presentation?
    let dismissAction: () -> Void
    let planStayAction: ((Region) -> Void)?

    @AccessibilityFocusState private var isCardFocused: Bool
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        // Keep the container mounted so the scrim never inherits the card's motion.
        ZStack {
            if let presentation {
                Color.black
                    .opacity(stylesheet.locationWelcome.scrimOpacity)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    .zIndex(0)

                GeometryReader { proxy in
                    ScrollView {
                        RegionWelcomeCard(
                            presentation: presentation,
                            dismissAction: dismissAction,
                            planStayAction: planStayAction,
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, stylesheet.spacing.xxxLarge)
                        .padding(.vertical, stylesheet.spacing.xxxLarge)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        .accessibilityFocused($isCardFocused)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isModal)
                .transition(stylesheet.locationWelcome.motion.transition)
                .zIndex(1)
                .onAppear {
                    isCardFocused = true
                    UIAccessibility.post(notification: .screenChanged, argument: nil)
                }
                .onDisappear {
                    isCardFocused = false
                    UIAccessibility.post(notification: .screenChanged, argument: nil)
                }
            }
        }
        .animation(stylesheet.locationWelcome.motion.animation, value: presentation)
    }
}

#if DEBUG
    #Preview {
        LocationWelcomeOverlay(
            presentation: .init(region: .california, greeting: .first),
            dismissAction: {},
            planStayAction: { _ in },
        )
        .whereBroadwayRoot()
    }
#endif
