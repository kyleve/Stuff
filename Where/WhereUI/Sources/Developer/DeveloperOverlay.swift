#if DEBUG
    import PeriscopeTools
    import SFSafeSymbols
    import SnapshotKit
    import SwiftUI
    import UIKit
    import WhereCore

    /// A global, DEBUG-only developer launcher and tool surface above the app.
    ///
    /// Collapsed, it's a small draggable button (``DeveloperOverlayButton``) that
    /// snaps to the nearest corner. Tapping unfolds a labeled glass accordion
    /// directly over the app; its clear backdrop consumes an outside tap without
    /// visually dimming the app. Choosing a route replaces the menu with the
    /// selected tool in a Liquid Glass HUD — draggable, resizable, and able to
    /// grow into an inset full-screen modal. Flyover is the exception: it owns an
    /// independent navigation domain and opens in a full-screen cover.
    ///
    /// The floating HUD reports its footprint through
    /// ``DeveloperOverlayInsetKey`` so app content scrolls clear of it. The tool
    /// host keeps its identity across floating/full-screen changes, preserving
    /// the tool's navigation state; closing it returns to the collapsed launcher.
    ///
    /// Attached once at ``RootView`` and compiled out of release (`#if DEBUG`).
    struct DeveloperOverlay: View {
        /// Native bar clearance measured on each edge by the active tab.
        /// RootView passes it to this sibling overlay. Zero when logged out.
        private let tabBarInset: EdgeInsets

        @State private var model: DeveloperOverlayModel
        @State private var isPresentingFlyover = false
        @State private var isPresentingDemoConfiguration = false
        @Environment(\.stylesheet) private var stylesheet
        @Environment(WhereDeveloperLaunchController.self) private var launchController:
            WhereDeveloperLaunchController?

        init(tabBarInset: EdgeInsets = EdgeInsets()) {
            self.tabBarInset = tabBarInset
            _model = State(initialValue: DeveloperOverlayModel())
        }

        init(tabBarInset: EdgeInsets = EdgeInsets(), model: DeveloperOverlayModel) {
            self.tabBarInset = tabBarInset
            _model = State(initialValue: model)
        }

        var body: some View {
            AdaptivePaneGeometryReader { geometry in
                DeveloperOverlayLayout(
                    geometry: geometry,
                    model: model,
                    openDestination: openDestination,
                    configureDemo: configureDemo,
                )
            }
            .padding(tabBarInset)
            .fullScreenCover(isPresented: $isPresentingFlyover) {
                WhereFlyoverPresentationView()
            }
            .sheet(isPresented: $isPresentingDemoConfiguration) {
                if let launchController {
                    DeveloperDemoLaunchSheet(controller: launchController)
                }
            }
            // Menu and full-screen states are modal to VoiceOver. Crossing either
            // boundary moves focus into/out of the active developer surface.
            .onChange(of: model.presentation) { old, new in
                let modalChanged = old.isAccessibilityModal != new.isAccessibilityModal
                UIAccessibility.post(
                    notification: modalChanged ? .screenChanged : .layoutChanged,
                    argument: nil,
                )
            }
        }

        private func configureDemo() {
            withAnimation(stylesheet.developerOverlay.menu.motion.animation) {
                model.closeMenu()
            }
            isPresentingDemoConfiguration = true
        }

        private func openDestination(_ destination: DeveloperDestination) {
            switch destination {
                case let .tool(tool):
                    withAnimation(stylesheet.developerOverlay.presentationAnimation) {
                        model.open(tool)
                    }
                case .flyover:
                    withAnimation(stylesheet.developerOverlay.menu.motion.animation) {
                        model.closeMenu()
                    }
                    isPresentingFlyover = true
            }
        }
    }

    extension DeveloperOverlay: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Collapsed", configurations: retainingScene(.phoneLightDark)) {
                DeveloperOverlayPreview(presentation: .collapsed)
            }
            whereSnapshot(
                name: "MenuBottomTrailing",
                configurations: retainingScene(.fullContentPhoneLightDark),
            ) {
                DeveloperOverlayPreview(presentation: .menu)
            }
            whereSnapshot(
                name: "MenuTopLeading",
                configurations: retainingScene(SnapshotConfiguration
                    .combinations(devices: [.iPhoneFullContent])),
            ) {
                DeveloperOverlayPreview(presentation: .menu, corner: .topLeading)
            }
            whereSnapshot(
                name: "SelectedTool",
                configurations: retainingScene(SnapshotConfiguration
                    .combinations(devices: [.iPhone])),
            ) {
                DeveloperOverlayPreview(presentation: .floating(.openSpans))
            }
        }

        /// Retain the scene for native glass; detached windows produce material bands
        /// and clipping in the menu captures.
        private static func retainingScene(
            _ configurations: [SnapshotConfiguration],
        ) -> [SnapshotConfiguration] {
            configurations.map { configuration in
                var configuration = configuration
                configuration.device.scenePolicy = .retained
                return configuration
            }
        }
    }

    /// Presents Flyover outside Developer Tools' navigation domain.
    private struct WhereFlyoverPresentationView: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            WhereFlyoverView()
                .overlay(alignment: .topLeading) {
                    WhereFlyoverCloseButton(action: dismiss.callAsFunction)
                }
        }
    }

    #Preview {
        WhereFlyoverPresentationView()
    }

    private struct WhereFlyoverCloseButton: View {
        let action: () -> Void

        var body: some View {
            Button(
                String(localized: .developerClose),
                systemSymbol: .xmark,
                action: action,
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .padding()
        }
    }

    #Preview {
        DeveloperOverlay.snapshotPreviews
    }
#endif

#if DEBUG
    extension DeveloperOverlay: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            DeveloperOverlay.self,
            title: "Developer Overlay",
            navigationContainer: .none,
            routes: [
                .push(to: WhereFlyoverLogView.flyoverID),
                .push(to: OpenSpansView.flyoverID),
                .push(to: RegionMapView.flyoverID),
            ],
        )
    }
#endif
