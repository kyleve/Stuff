import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct WhereBootstrapTests {
    @Test func coldRejectionStopsAndDiscardsThePreparedLocationSource() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let source = BootstrapLocationSource()
        var sourceCreations = 0
        let bootstrap = WhereBootstrap(
            installationContextStore: fixture.installation,
            storeStorage: .inMemory,
            coordinator: fixture.coordinator,
            makeLocationSource: {
                sourceCreations += 1
                return source
            },
            importReadiness: BootstrapImportReadiness(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            locationOutbox: NoOpLocationOutbox(),
        )
        bootstrap.prepareLocation()
        await bootstrap.withdrawHistoryOutputs()
        #expect(await source.stops == 1)
        bootstrap.prepareLocation()
        #expect(sourceCreations == 2)
        #expect(try fixture.installation.resolve().automaticRecordingEnabled == true)
    }

    @Test func discoveryObservesAnImportCompletedDuringAdmission() async throws {
        let store = try SwiftDataStore.inMemory()
        let readiness = BootstrapImportReadiness()
        let coordinator = DataCompatibilityCoordinator(
            storePreparation: DataCompatibilityStorePreparation(hasExistingHistory: false) {
                await readiness.recordImport()
                return store
            },
            source: .local(storeID: .init(rawValue: "bootstrap-fixture")),
            policy: .foundation,
            activationReadiness: .pendingValidation,
        )
        let bootstrap = WhereBootstrap(
            installationContextStore: makeInstallationRecordingContextStore(),
            storeStorage: .cloudKit(appGroupIdentifier: "isolated-fixture"),
            coordinator: coordinator,
            makeLocationSource: { BootstrapLocationSource() },
            importReadiness: readiness,
            widgetRefresher: NoopWidgetTimelineRefresher(),
            locationOutbox: NoOpLocationOutbox(),
        )
        let admission = try #require(try bootstrap.prepareDataCompatibility())
        _ = try await admission.refresh()
        #expect(try await bootstrap.discoverRecordingDevices().isEmpty)
    }
}
