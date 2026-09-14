import PeriscopeTools
import SwiftUI

/// The menu's shared row stack. Its parent owns scrolling, viewport bounds, and placement.
/// Rows remain mounted for the same asymmetric insertion and removal transitions.
struct DeveloperOverlayMenuContent: View {
    let isPresented: Bool
    let corner: DeveloperOverlayModel.Corner
    let onOpenDestination: (DeveloperDestination) -> Void
    let onConfigureDemo: () -> Void

    #if DEBUG
        @Environment(WhereDeveloperLaunchController.self) private var modeController:
            WhereDeveloperLaunchController?
        @Environment(\.periscopeInspector) private var inspector
    #endif
    @Environment(WhereModel.self) private var whereModel: WhereModel?
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let menu = stylesheet.developerOverlay.menu
        let destinations = DeveloperDestination.available.filter { destination in
            if destination == .tool(.porthole) { return whereModel?.porthole.isEnabled == true }
            return true
        }
        #if DEBUG
            let launchModeRowCount = modeController == nil ? 0 : 2
            let logModeRowCount = inspector == nil ? 0 : 1
        #else
            let launchModeRowCount = 0
            let logModeRowCount = 0
        #endif
        let itemCount = destinations.count + launchModeRowCount + logModeRowCount
        let origin: Edge = corner.isTop ? .top : .bottom

        LazyVStack(spacing: menu.rowSpacing) {
            ForEach(
                Array(destinations.enumerated()),
                id: \.element,
            ) { index, destination in
                if isPresented {
                    DeveloperToolMenuButton(destination: destination) {
                        onOpenDestination(destination)
                    }
                    .transition(
                        menu.motion.transition(
                            from: origin,
                            index: index,
                            itemCount: itemCount,
                        ),
                    )
                }
            }

            #if DEBUG
                if let modeController, isPresented {
                    DeveloperInspectorModeRow(controller: modeController)
                        .transition(
                            menu.motion.transition(
                                from: origin,
                                index: destinations.count,
                                itemCount: itemCount,
                            ),
                        )

                    DeveloperDemoModeRow(
                        controller: modeController,
                        action: onConfigureDemo,
                    )
                    .transition(
                        menu.motion.transition(
                            from: origin,
                            index: destinations.count + 1,
                            itemCount: itemCount,
                        ),
                    )
                }

                if let inspector, isPresented {
                    DeveloperLogViewModeRow(inspector: inspector)
                        .transition(
                            menu.motion.transition(
                                from: origin,
                                index: destinations.count + launchModeRowCount,
                                itemCount: itemCount,
                            ),
                        )
                }
            #endif
        }
    }
}

#if DEBUG
    #Preview {
        DeveloperOverlayPreview(presentation: .menu, isPortholeEnabled: true, surface: .menuContent)
    }

#endif
