#if DEBUG
    import PeriscopeTools
    import SFSafeSymbols
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
                        DeveloperLaunchModeMenuRows(
                            modeController: modeController,
                            origin: origin,
                            firstIndex: destinations.count,
                            itemCount: itemCount,
                            onConfigureDemo: onConfigureDemo,
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

    private struct DeveloperLaunchModeMenuRows: View {
        let modeController: WhereDeveloperLaunchController
        let origin: Edge
        let firstIndex: Int
        let itemCount: Int
        let onConfigureDemo: () -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            DeveloperInspectorModeRow(controller: modeController)
                .transition(
                    stylesheet.developerOverlay.menu.motion.transition(
                        from: origin,
                        index: firstIndex,
                        itemCount: itemCount,
                    ),
                )

            DeveloperDemoModeRow(
                controller: modeController,
                action: onConfigureDemo,
            )
            .transition(
                stylesheet.developerOverlay.menu.motion.transition(
                    from: origin,
                    index: firstIndex + 1,
                    itemCount: itemCount,
                ),
            )
        }
    }

    #Preview {
        DeveloperOverlayPreview(presentation: .menu)
    }

    /// One navigation action in the developer overlay's accordion.
    private struct DeveloperToolMenuButton: View {
        let destination: DeveloperDestination
        let action: () -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            Button(action: action) {
                Label(destination.title, systemSymbol: destination.systemSymbol)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, menu.horizontalPadding)
                    .padding(.vertical, menu.verticalPadding)
                    .frame(minHeight: menu.minRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: menu.cornerRadius),
            )
            .accessibilityInputLabels([destination.title])
        }
    }

    #Preview {
        DeveloperToolMenuButton(destination: .tool(.regionMap), action: {})
            .padding()
            .whereBroadwayRoot()
    }

    /// The accordion's next-launch Inspector control.
    ///
    /// Latching or clearing the preference never changes the current process
    /// runtime. A selected state stays visible as the row's subtitle and makes
    /// the same control the cancellation action.
    private struct DeveloperInspectorModeRow: View {
        @Bindable var controller: WhereDeveloperLaunchController

        var body: some View {
            DeveloperLaunchModeButton(
                title: title,
                subtitle: controller
                    .nextLaunch == .inspector ?
                    String(localized: .developerInspectorNextLaunchSelected) : nil,
                systemSymbol: systemSymbol,
                action: toggleNextLaunch,
            )
        }

        private var title: String {
            switch controller.nextLaunch {
                case .regularApplication, .demo:
                    String(localized: .developerEnterInspectorNextLaunch)
                case .inspector:
                    String(localized: .developerCancelInspectorNextLaunch)
            }
        }

        private var systemSymbol: SFSymbol {
            switch controller.nextLaunch {
                case .regularApplication, .demo: .wrenchAndScrewdriver
                case .inspector: .xmarkCircle
            }
        }

        private func toggleNextLaunch() {
            switch controller.nextLaunch {
                case .regularApplication, .demo:
                    controller.scheduleInspector()
                case .inspector:
                    controller.useRegularApplicationOnNextLaunch()
            }
        }
    }

    #Preview("DeveloperInspectorModeRow") {
        DeveloperOverlayPreview(presentation: .menu)
    }

    /// Opens the one-shot demo configuration for the next process launch.
    private struct DeveloperDemoModeRow: View {
        @Bindable var controller: WhereDeveloperLaunchController
        let action: () -> Void

        var body: some View {
            DeveloperLaunchModeButton(
                title: String(localized: .developerDemoNextLaunch),
                subtitle: subtitle,
                systemSymbol: .playRectangleOnRectangle,
                action: action,
            )
        }

        private var subtitle: String? {
            guard case let .demo(configuration) = controller.nextLaunch else { return nil }
            return summary(for: configuration)
        }

        private func summary(for configuration: DemoDataBuilder.Configuration) -> String {
            guard !configuration.issueCategories.isEmpty else {
                return String(localized: .developerDemoCleanBaseline)
            }
            return WhereFormat.resolutionCategoryList(configuration.issueCategories)
        }
    }

    #Preview("DeveloperDemoModeRow") {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
