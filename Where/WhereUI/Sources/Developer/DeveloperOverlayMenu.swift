#if DEBUG
    import PeriscopeTools
    import SwiftUI

    /// The lightweight Path-style developer menu layered over the app.
    ///
    /// It remains mounted while collapsed so each row can own an asymmetric
    /// insertion/removal transition: routes cascade away from the launcher when
    /// opening, then collapse toward it in reverse order.
    struct DeveloperOverlayMenu: View {
        let isPresented: Bool
        let corner: DeveloperOverlayModel.Corner
        let maxHeight: CGFloat
        let onOpenDestination: (DeveloperDestination) -> Void
        let onConfigureDemo: () -> Void

        @Environment(WhereDeveloperLaunchController.self) private var modeController:
            WhereDeveloperLaunchController?
        @Environment(\.periscopeInspector) private var inspector
        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            let destinations = DeveloperDestination.available
            let launchModeRowCount = modeController == nil ? 0 : 2
            let logModeRowCount = inspector == nil ? 0 : 1
            let itemCount = destinations.count + launchModeRowCount + logModeRowCount
            let origin: Edge = corner.isTop ? .top : .bottom

            ScrollView {
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
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(corner.isTop ? .top : .bottom)
            .frame(maxHeight: max(maxHeight, 0))
            .allowsHitTesting(isPresented)
            .accessibilityHidden(isPresented == false)
        }
    }

    #Preview {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
