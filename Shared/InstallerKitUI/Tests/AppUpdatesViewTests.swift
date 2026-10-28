import InstallerKit
@_spi(Testing) @testable import InstallerKitUI
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct AppUpdatesViewTests {
    @Test func pullRefreshFetchesDespiteCachedResult() async throws {
        let fixture = UpdatePageRefreshFixture()
        let host = UIHostingController(rootView: AppUpdatesView(
            model: fixture.model,
            branding: InstallerPreview.branding,
        ))
        try await show(host) { _ in
            try await fixture.checkRefresh(in: host)
        }
    }

    @Test func navigationReentryChecksThroughTheSameModelAndHonorsItsCache() throws {
        let preferences = UpdatePagePreferences()
        let client = UpdatePageClient(catalog: InstallerPreview.catalog(.available))
        let clock = UpdatePageClock()
        let model = UpdateModel(service: UpdateService(
            installed: InstallerPreview.distribution(),
            preferences: preferences,
            client: client,
            now: { clock.date },
        ))
        let navigation = UINavigationController(rootViewController: UIViewController())
        let page = UIHostingController(rootView: AppUpdatesView(
            model: model,
            branding: InstallerPreview.branding,
        ))

        try show(navigation) { _ in
            navigation.pushViewController(page, animated: false)
            try waitFor { model.needsAttention && !model.isChecking }
            #expect(client.requests == 1)

            navigation.popViewController(animated: false)
            try waitFor { page.view.window == nil }
            navigation.pushViewController(page, animated: false)
            try waitFor { page.view.window != nil && !model.isChecking }
            #expect(client.requests == 1)

            navigation.popViewController(animated: false)
            try waitFor { page.view.window == nil }
            clock.date += 3601
            navigation.pushViewController(page, animated: false)
            try waitFor { client.requests == 2 && !model.isChecking }
            #expect(model.state.snapshot?.checkedAt == clock.date)
            #expect(preferences.installerUpdates.cached?.checkedAt == clock.date)
        }
    }
}
