import BroadwayUI
import SwiftUI

struct WidgetExampleDeviceFrame: ViewModifier {
    let surface: WidgetExampleSurface
    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet.featureDiscovery
        let wallpaper = surface == .homeScreen ? style.widgets.wallpapers.home : style.widgets
            .wallpapers.lock
        content
            .dynamicTypeSize(...style.widgets.device.dynamicTypeLimit)
            .bTraitOverrides { traits, overrides in
                overrides.contentSizeCategory = min(
                    traits.contentSizeCategory,
                    .init(style.widgets.device.dynamicTypeLimit),
                )
            }
            .containerRelativeFrame(.horizontal) { length, _ in
                style.widgets.contentWidth(in: length)
            }
            .padding(style.widgets.device.padding)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [wallpaper.top, wallpaper.bottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                ),
                in: .rect(cornerRadius: style.widgets.device.cornerRadius),
            )
    }
}

#if DEBUG
    #Preview {
        WidgetExampleFrame(surface: .homeScreen) {
            TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot())
        }
        .modifier(WidgetExampleDeviceFrame(surface: .homeScreen))
        .whereBroadwayRoot()
    }
#endif
