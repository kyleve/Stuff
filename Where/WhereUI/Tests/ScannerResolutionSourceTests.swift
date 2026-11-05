import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct ScannerResolutionSourceTests {
    @Test func revokedAccessCannotPublishACompletedOrCachedScan() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let services = try await fixture.makeServices()
        let source = ScannerResolutionSource(services: services, preferences: makePreferences())
        await source.refreshResolution()
        #expect(source.resolutionState.scan != nil)
        await services.retireCompatibilityScope()
        await source.refreshResolution()
        #expect(source.resolutionState.scan == nil)
        #expect(source.resolutionState.error != nil)
    }

    @Test func retirementWhileScanCompletionIsHeldClearsPreviousContent() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let services = try await fixture.makeServices()
        let source = ScannerResolutionSource(services: services, preferences: makePreferences())
        await source.refreshResolution()
        await services.resolution.invalidate()
        let hold = ResolutionScanSuspension()
        await services.resolution.setBeforeHistoricalPublicationForTesting {
            await hold.suspendFirst()
        }
        let pending = Task { await source.refreshResolution() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        await services.retireCompatibilityScope()
        hold.resume()
        await pending.value
        #expect(source.resolutionState.scan == nil)
        #expect(source.resolutionState.error != nil)
    }

    @Test func supersededCompletionCannotReplaceTheNewerPublication() async throws {
        let store = try TestStore()
        let services = FlightReviewTestSupport.services(
            store: store,
            now: FlightReviewTestSupport.date(hour: 18),
        )
        let source = ScannerResolutionSource(services: services, preferences: makePreferences())
        let hold = ResolutionScanSuspension()
        await services.resolution.setBeforeHistoricalPublicationForTesting {
            await hold.suspendFirst()
        }
        let pending = Task { await source.refreshResolution() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        await source.refreshResolution()
        let latest = try #require(source.resolutionState.scan?.revision)
        hold.resume()
        await pending.value
        #expect(source.resolutionState.scan?.revision == latest)
    }

    @Test func cancellationKeepsTheLastPublication() async throws {
        let store = try TestStore()
        let services = FlightReviewTestSupport.services(
            store: store,
            now: FlightReviewTestSupport.date(hour: 18),
        )
        let source = ScannerResolutionSource(services: services, preferences: makePreferences())
        await source.refreshResolution()
        let previous = try #require(source.resolutionState.scan?.revision)
        await services.resolution.invalidate()
        let hold = ResolutionScanSuspension()
        await services.resolution.setBeforeHistoricalPublicationForTesting {
            await hold.suspendFirst()
        }
        let pending = Task { await source.refreshResolution() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        pending.cancel()
        hold.resume()
        await pending.value
        #expect(source.resolutionState.scan?.revision == previous)
        #expect(source.resolutionState.error == nil)
    }
}
