@testable import Flyover
import SwiftUI
import Testing

@MainActor
struct FlyoverCatalogTests {
    @Test func validCatalogHasNoIssues() {
        let catalog = makeFlyoverTestCatalog()

        #expect(catalog.isValid)
        #expect(catalog.validationIssues.isEmpty)
    }

    @Test func duplicateScreenIDsAreRejected() {
        let duplicate = testScreen(id: .root, title: "Duplicate")
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("first"),
                    title: "First",
                    root: .root,
                    screens: [testScreen(id: .root, title: "Root")],
                ),
                FlyoverGroup(
                    id: FlyoverGroupID("second"),
                    title: "Second",
                    root: .root,
                    screens: [duplicate],
                ),
            ],
        )

        #expect(catalog.validationIssues.contains(.duplicateScreenID(.root)))
    }

    @Test func duplicateGroupVariantAndControlIDsAreRejected() {
        let repeatedVariantID = FlyoverVariantID("repeated")
        let repeatedControlID = AnyHashable("repeated")
        let root = FlyoverScreen(
            id: FlyoverTestScreen.root,
            title: "Root",
            variants: [
                FlyoverVariant(id: repeatedVariantID, title: "First") {
                    EmptyView()
                },
                FlyoverVariant(id: repeatedVariantID, title: "Second") {
                    EmptyView()
                },
            ],
            controls: [
                FlyoverControl(id: repeatedControlID) {
                    EmptyView()
                },
                FlyoverControl(id: repeatedControlID) {
                    EmptyView()
                },
            ],
        )
        let repeatedGroupID = FlyoverGroupID("repeated")
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: repeatedGroupID,
                    title: "First",
                    root: .root,
                    screens: [root],
                ),
                FlyoverGroup(
                    id: repeatedGroupID,
                    title: "Second",
                    root: .pushed,
                    screens: [testScreen(id: .pushed, title: "Pushed")],
                ),
            ],
        )

        #expect(catalog.validationIssues.contains(.duplicateGroupID(repeatedGroupID)))
        #expect(
            catalog.validationIssues.contains(
                .duplicateVariantID(screen: .root, variant: repeatedVariantID),
            ),
        )
        #expect(
            catalog.validationIssues.contains(
                .duplicateControlID(screen: .root, control: repeatedControlID),
            ),
        )
    }

    @Test func missingRootsAndDanglingRoutesAreRejected() {
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("main"),
                    title: "Main",
                    root: .pushed,
                    screens: [testScreen(id: .root, title: "Root")],
                ),
            ],
            transitions: [
                FlyoverTransition(from: .root, to: .modal, kind: .push),
            ],
        )

        #expect(
            catalog.validationIssues.contains(
                .missingGroupRoot(group: FlyoverGroupID("main"), root: .pushed),
            ),
        )
        #expect(catalog.validationIssues.contains(.danglingTransitionEndpoint(.modal)))
    }

    @Test func duplicateRoutesAndPositionsAreRejected() {
        let first = testScreen(
            id: .root,
            title: "Root",
            position: FlyoverPosition(column: 0, row: 0),
        )
        let second = testScreen(
            id: .pushed,
            title: "Pushed",
            position: FlyoverPosition(column: 0, row: 0),
        )
        let transition = FlyoverTransition<FlyoverTestScreen>(
            from: .root,
            to: .pushed,
            kind: .push,
        )
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("main"),
                    title: "Main",
                    root: .root,
                    screens: [first, second],
                ),
            ],
            transitions: [transition, transition],
        )

        #expect(catalog.validationIssues.count == 2)
    }

    private func testScreen(
        id: FlyoverTestScreen,
        title: String,
        position: FlyoverPosition? = nil,
    ) -> FlyoverScreen<FlyoverTestScreen> {
        FlyoverScreen(
            id: id,
            title: title,
            position: position,
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
}
