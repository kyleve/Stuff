#if DEBUG
    import Flyover
    import SnapshotKit
    import SwiftUI

    /// One screen's lazy Flyover representation and outgoing navigation routes.
    @MainActor
    struct WhereFlyoverData {
        let id: WhereFlyoverScreenID
        let routes: [Route]
        private let screenBuilder:
            @MainActor (WhereFlyoverScreenID, WhereFlyoverWorld)
            -> FlyoverScreen<WhereFlyoverScreenID>

        init(
            _ screenType: (some View).Type,
            routes: [Route] = [],
            screen: @escaping @MainActor (
                WhereFlyoverScreenID,
                WhereFlyoverWorld,
            ) -> FlyoverScreen<WhereFlyoverScreenID>,
        ) {
            id = WhereFlyoverScreenID(screenType)
            self.routes = routes
            screenBuilder = screen
        }

        init(
            id: WhereFlyoverScreenID,
            routes: [Route] = [],
            screen: @escaping @MainActor (
                WhereFlyoverScreenID,
                WhereFlyoverWorld,
            ) -> FlyoverScreen<WhereFlyoverScreenID>,
        ) {
            self.id = id
            self.routes = routes
            screenBuilder = screen
        }

        func screen(in world: WhereFlyoverWorld) -> FlyoverScreen<WhereFlyoverScreenID> {
            screenBuilder(id, world)
        }

        var transitions: [FlyoverTransition<WhereFlyoverScreenID>] {
            routes.map { $0.transition(from: id) }
        }

        static func snapshots(
            _ screenType: (some View & SnapshotProviding).Type,
            title: String,
            viewport: FlyoverViewport = .device,
            navigationContainer: FlyoverNavigationContainer = .stack,
            routes: [Route] = [],
        ) -> Self {
            snapshots(
                screenType,
                id: WhereFlyoverScreenID(screenType),
                title: title,
                viewport: viewport,
                navigationContainer: navigationContainer,
                routes: routes,
            )
        }

        static func snapshots<Screen: View & SnapshotProviding>(
            _: Screen.Type,
            id: WhereFlyoverScreenID,
            title: String,
            viewport: FlyoverViewport = .device,
            navigationContainer: FlyoverNavigationContainer = .stack,
            routes: [Route] = [],
        ) -> Self {
            Self(id: id, routes: routes) { id, _ in
                FlyoverScreen(
                    id: id,
                    title: title,
                    viewport: viewport,
                    navigationContainer: navigationContainer,
                    variants: Screen.snapshots.flatMap { snapshotCase in
                        FlyoverVariant.snapshots(
                            id: FlyoverVariantID(snapshotCase.name),
                            snapshotCase: snapshotCase,
                        )
                    },
                )
            }
        }

        static func hosted(
            _ screenType: (some View).Type,
            title: String,
            viewport: FlyoverViewport = .device,
            navigationContainer: FlyoverNavigationContainer = .stack,
            routes: [Route] = [],
            @ViewBuilder content: @escaping @MainActor (WhereFlyoverWorld) -> some View,
        ) -> Self {
            Self(screenType, routes: routes) { id, world in
                FlyoverScreen(
                    id: id,
                    title: title,
                    viewport: viewport,
                    navigationContainer: navigationContainer,
                    variants: [
                        hostedVariant(
                            id: "default",
                            title: "Default",
                            world: world,
                        ) {
                            content(world)
                        },
                    ],
                )
            }
        }

        static func hostedVariant(
            id: String,
            title: String,
            world: WhereFlyoverWorld,
            @ViewBuilder content: @escaping @MainActor () -> some View,
        ) -> FlyoverVariant {
            FlyoverVariant(id: FlyoverVariantID(id), title: title) {
                WhereFlyoverHost(world: world, content: content)
            }
        }

        enum Route {
            case push(to: WhereFlyoverScreenID)
            case modal(to: WhereFlyoverScreenID)

            fileprivate func transition(
                from source: WhereFlyoverScreenID,
            ) -> FlyoverTransition<WhereFlyoverScreenID> {
                switch self {
                    case let .push(destination):
                        FlyoverTransition(from: source, to: destination, kind: .push)
                    case let .modal(destination):
                        FlyoverTransition(from: source, to: destination, kind: .modal)
                }
            }
        }
    }

    /// Injects the isolated Flyover world and Where's style root around app content.
    private struct WhereFlyoverHost<Content: View>: View {
        let world: WhereFlyoverWorld
        @ViewBuilder let content: Content

        var body: some View {
            content
                .environment(world.model)
                .environment(world.session)
                .environment(\.isInDemoMode, true)
                .environment(\.demoExitPresentation, .embedded)
                .whereBroadwayRoot(regionStyles: world.session.regionStyles)
        }
    }

    #Preview {
        WhereFlyoverHost(world: .preview()) {
            Text("Flyover content")
        }
    }
#endif
