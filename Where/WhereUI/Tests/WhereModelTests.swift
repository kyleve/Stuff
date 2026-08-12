import Foundation
@_spi(Testing) import PeriscopeCore
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

private struct WhereModelWaitTimeout: Error {}

private actor ThemeChangeGate {
    private(set) var isBlocked = false
    private(set) var delivered: [WhereTheme] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func receive(_ theme: WhereTheme) async {
        if theme == .alternate {
            isBlocked = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            guard !Task.isCancelled else { return }
        }
        delivered.append(theme)
    }

    func release() {
        continuation?.resume()
        continuation = nil
        isBlocked = false
    }
}

private actor ThemeRecorder {
    private(set) var delivered: [WhereTheme] = []

    func receive(_ theme: WhereTheme) {
        delivered.append(theme)
    }
}

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

    @Test func loadsPreviewsCommitsAndResetsTheme() throws {
        let preferences = makePreferences()
        preferences.theme = .alternate
        let model = try WhereModel(
            services: makeServices(),
            preferences: preferences,
            logSystem: .isolated(),
        )

        #expect(model.theme == .alternate)
        model.previewTheme(.standard)
        #expect(model.theme == .standard)
        #expect(preferences.theme == .alternate)

        model.completeOnboarding()
        #expect(preferences.theme == .standard)

        model.selectTheme(.alternate)
        #expect(model.theme == .alternate)
        #expect(preferences.theme == .alternate)

        try model.resetPreferences()
        #expect(model.theme == .standard)
        #expect(preferences.theme == .standard)
    }

    @Test func repeatedThemeSelectionsCancelSupersededUpdates() async throws {
        let model = try WhereModel(
            services: makeServices(),
            preferences: makePreferences(),
            logSystem: .isolated(),
        )
        let gate = ThemeChangeGate()
        model.onThemeChanged = { await gate.receive($0) }

        model.selectTheme(.alternate)
        while await !gate.isBlocked {
            await Task.yield()
        }
        model.selectTheme(.standard)
        await gate.release()
        try await waitForWhereModel { model.theme == .standard }
        while await gate.delivered.isEmpty {
            await Task.yield()
        }

        #expect(await gate.delivered == [.standard])
    }

    @Test func onboardingCommitLaunchSynchronizationAndResetPublishTheme() async throws {
        let preferences = makePreferences()
        let model = try WhereModel(
            services: makeServices(),
            preferences: preferences,
            logSystem: .isolated(),
        )
        let recorder = ThemeRecorder()
        model.onThemeChanged = { await recorder.receive($0) }

        model.previewTheme(.alternate)
        model.completeOnboarding()
        while await recorder.delivered.count < 1 {
            await Task.yield()
        }
        #expect(await recorder.delivered == [.alternate])

        model.synchronizeTheme()
        while await recorder.delivered.count < 2 {
            await Task.yield()
        }
        #expect(await recorder.delivered == [.alternate, .alternate])

        try model.resetPreferences()
        while await recorder.delivered.count < 3 {
            await Task.yield()
        }
        #expect(await recorder.delivered == [.alternate, .alternate, .standard])
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

    @Test func themePreviewDoesNotPersistUntilOnboardingCompletes() throws {
        let preferences = makePreferences()
        let model = try WhereModel(
            services: makeServices(),
            preferences: preferences,
            logSystem: .isolated(),
        )

        model.previewTheme(.glass)

        #expect(model.theme == .glass)
        #expect(preferences.theme == .folio)

        model.completeOnboarding()

        #expect(preferences.theme == .glass)
        #expect(preferences.hasOnboarded)
    }

    @Test func settingsThemeSelectionPersistsImmediately() throws {
        let preferences = makePreferences()
        let model = try WhereModel(
            services: makeServices(),
            preferences: preferences,
            logSystem: .isolated(),
        )

        model.selectTheme(.glass)

        #expect(model.theme == .glass)
        #expect(preferences.theme == .glass)
    }
}
