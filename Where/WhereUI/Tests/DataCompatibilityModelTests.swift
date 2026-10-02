import Foundation
import LifecycleKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct DataCompatibilityModelTests {
    @Test func coldHeadlessLaunchWaitsAndResumesWithTheSameStore() async throws {
        let store = try SwiftDataStore.inMemory()
        try await CompatibilityPresentationTestSupport.block(store)
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        let bootstrap = ScriptedBootstrap(services: services)
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let context = makeInstallationRecordingContextStore()
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: context,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        var handoffs = 0
        let runner = WhereLaunch
            .makeLauncher(model: model, reason: .background(.location)) { _ in handoffs += 1 }
        let launch = Task { await runner.run() }
        defer { launch.cancel(); model.compatibility.detach() }
        try await CompatibilityPresentationTestSupport.waitUntil {
            if case .updateRequired = model.compatibility.state { return true }; return false
        }
        #expect(bootstrap.makeServicesCount == 0)
        #expect(handoffs == 0)
        #expect(await !services.ingestor.isActive)
        #expect(try await store.deviceDataCapabilities()
            .contains { $0.supportedVersion == .initial })
        // An upgraded build resumes the suspended launch. Retry never lowers the requirement.
        await store
            .setSupportedDataCompatibilityVersionForTesting(CompatibilityPresentationTestSupport
                .future)
        #expect(await model.refreshCompatibility())
        await launch.value
        #expect(bootstrap.makeServicesCount == 1)
        #expect(handoffs == 1)
        #expect(model.session != nil)
        #expect(try await store.dataCompatibility()
            .requiredVersion == CompatibilityPresentationTestSupport.future)
        #expect(context.onboardingContext.automaticRecordingEnabled == true)
        try await services.recording.retireForRejoin()
        await services.ingestor.pause()
    }

    @Test func remoteRequirementStopsRecordingWithoutChangingConsent() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        let preferences = makePreferences()
        let model = WhereModel(services: services, preferences: preferences, logSystem: .isolated())
        try await model.prepareCompatibility(publishCapability: false)
        let session = try #require(model.session)
        await session.syncAuthorization()
        await session.reconcileTracking()
        #expect(await services.ingestor.isActive)
        try await CompatibilityPresentationTestSupport.block(store)
        try await CompatibilityPresentationTestSupport.waitUntil {
            let active = await services.ingestor.isActive
            return model.compatibility.state?.allowsData == false && !active
        }
        #expect(model.installationRecordingContext.automaticRecordingEnabled == true)
        await store
            .setSupportedDataCompatibilityVersionForTesting(CompatibilityPresentationTestSupport
                .future)
        #expect(await model.refreshCompatibility())
        try await CompatibilityPresentationTestSupport
            .waitUntil { await services.ingestor.isActive }
        model.compatibility.detach()
        try await services.recording.retireForRejoin()
        await services.ingestor.pause()
    }

    @Test func blockedForegroundStillReportsSupportWithRecordingOff() async throws {
        let store = try SwiftDataStore.inMemory()
        try await CompatibilityPresentationTestSupport.block(store)
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        let context = makeInstallationRecordingContextStore()
        try context.setAutomaticRecordingEnabled(false)
        let bootstrap = ScriptedBootstrap(services: services)
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: context,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        defer { model.compatibility.detach() }
        #expect(await !model.refreshCompatibility())
        let before = try #require(try await store.deviceDataCapabilities().first)
        #expect(await !model.refreshCompatibility())
        let after = try #require(try await store.deviceDataCapabilities().first)
        #expect(after.revision > before.revision)
        #expect(after.supportedVersion == .initial)
        #expect(context.onboardingContext.automaticRecordingEnabled == false)
        #expect(bootstrap.makeServicesCount == 0)
    }

    @Test func oneShotCompletionCannotEscapeCompatibilitySuspension() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = GatedCurrentLocationSource()
        let services = CompatibilityPresentationTestSupport.services(store: store, source: source)
        let request = Task { await services.ingestor.currentLocation() }
        await source.waitUntilRequestCount(1)
        try await CompatibilityPresentationTestSupport.block(store)
        await services.compatibilityRuntime.suspend()
        await source.resolveRequest(at: 0, with: LocationSample(
            timestamp: Date(),
            coordinate: .init(latitude: 0, longitude: 0),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        ))
        #expect(await request.value == .unavailable(.cancellation))
        #expect(await services.ingestor.currentLocation() == .unavailable(.cancellation))
    }

    @Test func verificationFailureRemainsRetryableAndDoesNotLookCompatible() async throws {
        let store = try TestStore()
        await store.failCompatibilityVerification(true)
        let resources = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        ).compatibilityServices
        let model = DataCompatibilityModel()
        await model.attach(resources) { _, _ in }
        if case .verificationFailed = model.state {}
        else { Issue.record("Expected a verification failure") }
        #expect(throws: DataCompatibilityError.self) { try model.requireAccess() }
        await store.failCompatibilityVerification(false)
        await model.refresh(publishCapability: true)
        #expect(model.state?.allowsData == true)
        model.detach()
    }
}
