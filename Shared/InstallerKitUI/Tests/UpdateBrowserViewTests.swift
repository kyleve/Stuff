import InstallerKit
@_spi(Testing) @testable import InstallerKitUI
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct UpdateBrowserViewTests {
    @Test func pullRefreshFetchesDespiteCachedResult() async throws {
        let fixture = UpdatePageRefreshFixture()
        let host = UIHostingController(rootView: UpdateBrowserView(
            model: fixture.model,
            branding: InstallerPreview.branding,
        ))
        try await show(host) { _ in
            try await fixture.checkRefresh(in: host)
        }
    }

    @Test(arguments: [false, true])
    func channelHistoryAndOlderBuildRoutesReturnAndReenterWithTheSameModel(isLocal: Bool) throws {
        let client = UpdatePageClient(catalog: InstallerBrowserPreview.catalog(.available))
        let clock = UpdatePageClock()
        let installed = isLocal ? InstallerPreview
            .localBuild(revision: .dirty(InstallerPreview.installedRevision)) : InstallerPreview
            .distribution()
        let model = UpdateModel(service: UpdateService(
            installed: installed,
            preferences: UpdatePagePreferences(),
            client: client,
            now: { clock.date },
        ))
        let navigation = UpdateBrowserNavigationFixture()
        let host = UIHostingController(rootView: UpdateBrowserTestHost(
            model: model,
            navigation: navigation,
        ))
        try show(host) { _ in
            try waitFor {
                !model.isChecking && model.state.snapshot != nil &&
                    installerNavigationController(in: host) != nil
            }
            let stack = try #require(installerNavigationController(in: host))
            @MainActor func waitForPage(
                _ page: UpdateBrowserNavigationFixture.Page,
                depth: Int,
            ) throws {
                do {
                    try waitFor {
                        stack.viewControllers.count == depth && navigation.visiblePage == page &&
                            stack.topViewController?.viewIfLoaded?.window != nil
                    }
                } catch {
                    throw TestHostError(
                        "Expected browser \(page) at depth \(depth), got \(navigation.visiblePage) at \(stack.viewControllers.count): \(error)",
                    )
                }
            }
            @MainActor func navigate(to path: [UpdateBrowserView.Route]) {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { navigation.path = path }
            }
            let main = InstallerBrowserPreview.selection(channel: .main, run: 14)
            try waitForPage(.channels, depth: 1)
            navigate(to: [.build(main)])
            try waitForPage(.destination(.build(main)), depth: 2)
            navigate(to: [.build(main), .history(main.channel)])
            try waitForPage(.destination(.history(main.channel)), depth: 3)
            navigate(to: [])
            try waitForPage(.channels, depth: 1)

            let older = InstallerBrowserPreview.selection(
                channel: InstallerPreview.channel,
                run: 11,
            )
            navigate(to: [.history(older.channel)])
            try waitForPage(.destination(.history(older.channel)), depth: 2)
            navigate(to: [.history(older.channel), .build(older)])
            try waitForPage(.destination(.build(older)), depth: 3)
            #expect(client.requests == 1)
            #expect(model.needsAttention == !isLocal)
            #expect(model.installed == installed)

            navigate(to: [])
            try waitForPage(.channels, depth: 1)
            clock.date += 3601
            navigate(to: [.build(InstallerBrowserPreview.selection(
                channel: InstallerBrowserPreview.otherChannel,
                run: 9,
            ))])
            try waitFor { client.requests >= 2 && !model.isChecking }
            #expect(model.state.snapshot?.checkedAt == clock.date)
            #expect(model.installed == installed)
        }
    }
}
