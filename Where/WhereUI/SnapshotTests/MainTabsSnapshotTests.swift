import SnapshotKit
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct MainTabsSnapshotTests {
    @Test func mainTabs() async {
        await assertSnapshots(of: SharedWorldSnapshots.self)
    }

    @Test(.timeLimit(.minutes(1)))
    func retryWaitsForItsMountedActivationDespitePreloadedData() async throws {
        let store = try TestStore()
        let now = PreviewSupport.referenceNow
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            now: { now },
        )
        let preferences = PreviewSupport.previewPreferences()
        preferences.showsLocationWelcome = false
        let session = WhereSession(services: services, preferences: preferences, now: { now })
        let report = YearReportModel(
            services: services,
            details: YearReportDetails(
                primaryRegions: [.california, .newYork],
                report: YearReport(year: PreviewSupport.year, days: [], totals: [:]),
                primaryRegionLocations: [:],
            ),
            selectedYear: PreviewSupport.year,
            preferences: preferences,
            now: { now },
        )
        defer { report.deactivate() }
        let readiness = MainTabsSnapshotReadiness()
        // Match captureConfiguredSnapshot: build once, then reuse this value in fresh hosts.
        let content = MainTabs(
            session: session,
            report: report,
            welcome: LocationWelcomeModel(
                services: services,
                preferences: preferences,
                now: { now },
            ),
            selection: .settings,
            snapshotReadiness: readiness,
        )
        .environment(session)
        .environment(PreviewSupport.loadedModel())
        .environment(\.scenePhase, .inactive)
        .whereBroadwayRoot()
        try waitFor { hostKeyWindow() != nil }
        var attempts = 0
        _ = try await SnapshotCaptureRetry.capture(
            named: "MainTabsActivationRetry",
            makeViewController: {
                let host = UIHostingController(rootView: content)
                SnapshotConfiguration(device: .iPhone).applyTraits(to: host)
                host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
                return host
            },
            capture: { controller in
                attempts += 1
                return try await renderSnapshotImage(
                    of: controller,
                    named: "MainTabsActivationRetry",
                    prepareForCapture: {
                        if attempts == 1 {
                            await readiness.waitForActivation()
                            #expect(report.dataIssueScan != nil)
                            await store.enableFirstSamplesGate()
                            throw SnapshotRenderingError.settleTimedOut(
                                name: "MainTabsActivationRetry",
                                phase: "forced retry after activation",
                                viewType: "MainTabs",
                                budget: 0,
                            )
                        }
                        var completed = false
                        let waiter = Task.immediate {
                            await readiness.waitForActivation()
                            completed = true
                        }
                        defer { waiter.cancel() }
                        await store.awaitFirstSamplesCall()
                        // The model remains loaded from attempt one while this mount is blocked.
                        if case .loaded = report.loadState {} else {
                            Issue.record("Expected the preloaded report to remain loaded")
                        }
                        #expect(!completed)
                        await store.releaseFirstSamplesCall()
                        await withTaskCancellationHandler {
                            await waiter.value
                        } onCancel: {
                            waiter.cancel()
                        }
                        #expect(completed)
                    },
                )
            },
            report: { _ in },
        )
        #expect(attempts == 2)
    }

    private enum SharedWorldSnapshots: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            MainTabs.snapshots(buildWorld: SnapshotWorldFixture.shared.load)
        }
    }
}
