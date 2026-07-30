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
                    testScreen(.root, title: "Root"),
                    testScreen(.pushed, title: "Pushed"),
                    testScreen(.modal, title: "Modal"),
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
private func testScreen(
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
