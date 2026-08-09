#if DEBUG
    import Flyover
    import SwiftUI

    private enum PatchlightFlyoverScreenID: String, Hashable {
        case dashboard
        case onboarding
    }

    /// A live map of Patchlight's currently shipping screens.
    @MainActor
    struct PatchlightFlyoverView: View {
        private let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("app"),
                    title: "App flow",
                    root: PatchlightFlyoverScreenID.dashboard,
                    screens: [
                        FlyoverScreen(
                            id: PatchlightFlyoverScreenID.dashboard,
                            title: "Dashboard",
                            variants: [
                                FlyoverVariant(
                                    id: FlyoverVariantID("signed-out"),
                                    title: "Signed out",
                                ) {
                                    PatchlightDashboardView().patchlightBroadwayRoot()
                                },
                            ],
                        ),
                        FlyoverScreen(
                            id: PatchlightFlyoverScreenID.onboarding,
                            title: "GitHub onboarding",
                            variants: [
                                FlyoverVariant(
                                    id: FlyoverVariantID("intro"),
                                    title: "Introduction",
                                ) {
                                    PatchlightOnboardingView(
                                        model: PatchlightAppModel(dependencies: .preview),
                                    )
                                    .patchlightBroadwayRoot()
                                },
                            ],
                        ),
                    ],
                ),
            ],
            transitions: [
                FlyoverTransition(
                    from: PatchlightFlyoverScreenID.dashboard,
                    to: .onboarding,
                    kind: .modal,
                ),
            ],
        )

        var body: some View {
            FlyoverView(catalog: catalog)
        }
    }

    #Preview {
        PatchlightFlyoverView()
    }
#endif
