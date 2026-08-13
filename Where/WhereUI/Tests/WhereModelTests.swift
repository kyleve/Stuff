import Foundation
@_spi(Testing) import PeriscopeCore
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

private struct WhereModelWaitTimeout: Error {}

@MainActor
private func waitForWhereModel(
    _ predicate: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while predicate() == false {
        if ContinuousClock.now >= deadline {
            throw WhereModelWaitTimeout()
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// Covers the process model's observable mirrors of scope-owned resources.
@MainActor
struct WhereModelTests {
    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    @Test func lateLogStoreArrivalPublishesReadyState() async throws {
        let store = try await PeriscopeStore.inMemory(
            session: .current(attributes: [:]),
        )
        let bootstrap = try ScriptedBootstrap(
            services: makeServices(),
            logStore: store,
        )
        bootstrap.gateLogStore()
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: makeInstallationRecordingContextStore(),
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )

        _ = try await model.resolveScope()
        guard case .opening = model.logStoreState else {
            Issue.record("Expected the durable log store to be opening.")
            return
        }

        bootstrap.releaseLogStore()
        try await waitForWhereModel {
            if case .ready = model.logStoreState { return true }
            return false
        }

        #expect(model.logStore === store)
    }

    @Test func logStoreFailurePublishesItsDiagnostic() async throws {
        let bootstrap = try FailingLogStoreBootstrap(services: makeServices())
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: makeInstallationRecordingContextStore(),
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )

        _ = try await model.resolveScope()
        try await waitForWhereModel {
            if case .failed = model.logStoreState { return true }
            return false
        }

        guard case let .failed(description) = model.logStoreState else {
            Issue.record("Expected the durable log store failure.")
            return
        }
        #expect(description == "scripted log store failure")
        #expect(model.logStore == nil)
    }

    @Test func assemblyWithoutDurableLoggingDoesNotStayOpening() async throws {
        let bootstrap = try ScriptedBootstrap(services: makeServices())
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: makeInstallationRecordingContextStore(),
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )

        _ = try await model.resolveScope()
        try await waitForWhereModel {
            if case .unavailable = model.logStoreState { return true }
            return false
        }

        #expect(model.logStore == nil)
    }

    @Test func attachingLogStoreExposesItOnTheModel() async throws {
        let model = try WhereModel(
            services: makeServices(),
            preferences: makePreferences(),
            logSystem: .isolated(),
        )
        let store = try await PeriscopeStore.inMemory(
            session: .current(attributes: [:]),
        )

        model.attach(logStore: store)

        guard case let .ready(published) = model.logStoreState else {
            Issue.record("Expected the attached log store to be ready.")
            return
        }
        #expect(published === store)
        #expect(model.logStore === store)
    }
}
