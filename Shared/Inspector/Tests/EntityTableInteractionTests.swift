import AccessibilitySnapshotParser
@testable import Inspector
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct EntityTableInteractionTests {
    @Test func selectedRowReturnsToItsPageAndLoadsMoreAfterCancellingDeletion() async throws {
        let container = try makeContainer()
        seed(container, widgets: 5, gadgets: 0)
        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container, rowLimit: 2),
        )
        await model.loadEntities()
        let entity = try #require(model.entities.first { $0.name == "TestWidget" })
        let host = UIHostingController(rootView: NavigationStack { EntityTableView(
            model: model,
            entity: entity,
        ) })

        try await show(host) { controller in
            let window = try #require(controller.view.window)
            window.layer.speed = 1
            try await waitForHostedState("Wait for the first table page", in: window) { visible(
                "Showing 2 of 5 rows",
                in: window,
            ) }
            let navigation = try #require(navigationController(in: controller))
            let tableDepth = navigation.viewControllers.count
            try await activateHostedButton("widget row", in: window) { $0.contains("Widget ") }
            try await waitForHostedState("Show selected row attributes", in: window) {
                navigation.viewControllers.count == tableDepth + 1 && visible(
                    "Attributes",
                    in: window,
                )
            }

            try await activateHostedButton("Delete Row", in: window) { $0 == "Delete Row" }
            try await waitForHostedState("Present destructive row confirmation", in: window) {
                presentedAlert(from: window.rootViewController)?.actions.contains {
                    $0.style == .destructive && $0.title == "Delete Row"
                } == true
            }
            let alert = try #require(presentedAlert(from: window.rootViewController))
            let cancel = try #require(alert.actions.first { $0.style == .cancel }?.title)
            // A toolbar-anchored confirmation can expose its cancellation on
            // the presentation container, outside the alert's action list.
            let presentation = try #require(alert.presentationController)
            let cancellationSurfaces: [NSObject] = [alert, alert.view, presentation] +
                [presentation.containerView].compactMap(\.self)
            if !cancellationSurfaces.contains(where: { $0.accessibilityPerformEscape() }) {
                try await activateHostedButton("Cancel the deletion confirmation", in: window) {
                    $0 == cancel || $0 == "Close" || $0.localizedCaseInsensitiveContains("dismiss")
                }
            }
            try await waitForHostedState("Dismiss cancelled deletion", in: window) {
                presentedAlert(from: window.rootViewController) == nil
            }
            #expect(navigation.viewControllers.count == tableDepth + 1)
            #expect(try await model.rows(for: entity).totalCount == 5)

            navigation.popViewController(animated: false)
            try await waitForHostedState("Return to the first table page", in: window) { visible(
                "Showing 2 of 5 rows",
                in: window,
            ) }
            try await activateHostedButton("Load more", in: window) { $0 == "Load more" }
            try await waitForHostedState("Display the next table page", in: window) { visible(
                "Showing 4 of 5 rows",
                in: window,
            ) }
        }
    }

    private func visible(_ label: String, in window: UIWindow) -> Bool {
        hostedAccessibilityObjects(in: window).contains {
            $0.accessibilityLabel?.localizedCaseInsensitiveCompare(label) == .orderedSame && $0
                .accessibilityFrame.intersects(window.bounds)
        }
    }

    private func navigationController(in controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController {
            return navigation
        }
        return controller.children.lazy.compactMap { navigationController(in: $0) }.first
    }

    private func presentedAlert(from controller: UIViewController?) -> UIAlertController? {
        guard let controller else { return nil }
        if let alert = controller as? UIAlertController {
            return alert
        }
        if let alert = presentedAlert(from: controller.presentedViewController) {
            return alert
        }
        return controller.children.lazy.compactMap { presentedAlert(from: $0) }.first
    }
}
