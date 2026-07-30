#if DEBUG
    import PeriscopeTools
    import SwiftUI
    import WhereCore

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

        @Environment(WhereModel.self) private var model: WhereModel?
        @Environment(WhereSession.self) private var session: WhereSession?
        @Environment(\.periscopeInspector) private var inspector
        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            let destinations = DeveloperDestination.available(
                hasLogStore: model?.logStore != nil,
                hasInspector: session?.swiftDataInspectorConfiguration != nil,
            )
            let itemCount = destinations.count + (inspector == nil ? 0 : 1)
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

                    if let inspector, isPresented {
                        DeveloperLogViewModeRow(inspector: inspector)
                            .transition(
                                menu.motion.transition(
                                    from: origin,
                                    index: destinations.count,
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
