import RegionKit
import SwiftUI
import UIKit

/// The modal scrim and adaptive placement for an app-wide welcome card.
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

                AdaptiveHistoryGeometryReader { geometry in
                    let area = geometry.unobstructedBounds(near: CGPoint(
                        x: geometry.contentBounds.midX,
                        y: geometry.contentBounds.maxY,
                    ))
                    ScrollView {
                        RegionWelcomeCard(
                            presentation: presentation,
                            dismissAction: dismissAction,
                            planStayAction: planStayAction,
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, stylesheet.spacing.xxxLarge)
                        .padding(.vertical, stylesheet.spacing.xxxLarge)
                        .frame(maxWidth: .infinity, minHeight: area.height)
                        .accessibilityFocused($isCardFocused)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: area.width, height: area.height)
                    .position(x: area.midX, y: area.midY)
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
        .animation(stylesheet.locationWelcome.motion.scrimAnimation, value: presentation)
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
