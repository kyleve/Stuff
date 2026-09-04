@testable import Flyover
import SwiftUI

@MainActor
func makeFlyoverTestCatalog() -> FlyoverCatalog<FlyoverTestScreen> {
    FlyoverCatalog(
        groups: [
            FlyoverGroup(
                id: FlyoverGroupID("main"),
                title: "Main",
                root: .root,
                screens: [
                    makeFlyoverTestScreen(.root, title: "Root"),
                    makeFlyoverTestScreen(.pushed, title: "Pushed"),
                    makeFlyoverTestScreen(.modal, title: "Modal"),
                ],
            ),
        ],
        transitions: [
            FlyoverTransition(from: .root, to: .pushed, kind: .push),
            FlyoverTransition(from: .root, to: .modal, kind: .modal),
        ],
    )
}

@MainActor
func makeFlyoverTestScreen(
    _ id: FlyoverTestScreen,
    title: String,
) -> FlyoverScreen<FlyoverTestScreen> {
    FlyoverScreen(
        id: id,
        title: title,
        variants: [
            FlyoverVariant(
                id: FlyoverVariantID("default"),
                title: "Default",
            ) {
                Text(title)
            },
        ],
    )
}
