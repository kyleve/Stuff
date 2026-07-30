@testable import Flyover
import SwiftUI
import Testing

@MainActor
struct FlyoverScreenTests {
    @Test func navigationStacksAreProvidedByDefaultAndCanBeDisabled() {
        let isolated = screen()
        let selfContained = screen(navigationContainer: .none)

        #expect(isolated.navigationContainer == .stack)
        #expect(selfContained.navigationContainer == .none)
    }

    private func screen(
        navigationContainer: FlyoverNavigationContainer = .stack,
    ) -> FlyoverScreen<FlyoverTestScreen> {
        FlyoverScreen(
            id: .root,
            title: "Root",
            navigationContainer: navigationContainer,
            variants: [
                FlyoverVariant(id: FlyoverVariantID("default"), title: "Default") {
                    EmptyView()
                },
            ],
        )
    }
}
