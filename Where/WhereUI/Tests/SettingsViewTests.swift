import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

/// Exercises every typed Settings route through the production navigation
/// stack. This is also the executable tripwire for oversized concrete content
/// stored by `SettingsFocusScope` while SwiftUI prepares a destination.
@MainActor
struct SettingsViewTests {
    @Test func everyPushDestinationHostsThroughProductionNavigation() throws {
        let report = PreviewSupport.loadedYearReportModel()
        let model = PreviewSupport.loadedModel()
        let session = PreviewSupport.loadedSession()

        for destination in SettingsDestination.allCases where !destination.isSheet {
            let rootView = SettingsView(
                report: report,
                testingRoute: SettingsRoute(destination),
            )
            .environment(model)
            .environment(session)

            try show(UIHostingController(rootView: rootView)) { hosted in
                try waitFor {
                    hosted.viewIfLoaded?.window != nil
                        && navigationController(in: hosted)?.viewControllers.count == 2
                }
            }
        }
    }

    private func navigationController(
        in viewController: UIViewController,
    ) -> UINavigationController? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        for child in viewController.children {
            if let navigationController = navigationController(in: child) {
                return navigationController
            }
        }
        return nil
    }
}
