import SFSafeSymbols
import SwiftUI

struct RegionWelcomeDismissButton: View {
    let welcome: WhereStylesheet.LocationWelcomeStyle
    let tint: Color
    let dismissAction: () -> Void

    var body: some View {
        Button(action: dismissAction) {
            Label(String(localized: .locationWelcomeDismiss), systemSymbol: .xmark)
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .background {
            if welcome.close.surface.usesReflection {
                Circle()
                    .fill(.background)
                    .opacity(welcome.paperOpacity)
            }
        }
        .buttonStyle(welcome.close.buttonStyle(tint: tint))
        .modifier(RegionWelcomeCloseSurface(style: welcome.close, tint: tint))
        .contentShape(Circle())
        .shadow(
            color: tint.opacity(welcome.close.glow.opacity),
            radius: welcome.close.glow.radius,
            y: welcome.close.glow.offsetY,
        )
        .shadow(
            color: .black.opacity(welcome.close.lift.opacity),
            radius: welcome.close.lift.radius,
            y: welcome.close.lift.offsetY,
        )
        .offset(welcome.close.offset)
    }
}

#if DEBUG
    #Preview("Welcome") {
        RegionWelcomeCard(
            presentation: .init(region: .newYork, greeting: .returnVisit),
            dismissAction: {},
            planStayAction: { _ in },
        )
        .whereBroadwayRoot()
    }
#endif
