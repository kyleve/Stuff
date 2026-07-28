import PeriscopeCore
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
import WhereUI

/// Reads the flag the way every real consumer does, and records what it saw.
private struct DemoModeProbe: View {
    @Environment(\.isInDemoMode) private var isInDemoMode
    let onRead: (Bool) -> Void

    var body: some View {
        Color.clear.onAppear { onRead(isInDemoMode) }
    }
}

/// Covers the seam between "which world the model is in" and "what the views
/// see": `RootView` seeds `\.isInDemoMode` through `demoMode(of:)`, and
/// Settings' way out of demo mode is the only thing that reveals it. A missing
/// injection would strand a user in the demo with no exit, so the mapping is
/// tested rather than left to an inline expression at the app root.
@MainActor
struct DemoModeEnvironmentTests {
    private func readValue(from model: WhereModel) throws -> Bool {
        var seen: Bool?
        let host = UIHostingController(rootView: AnyView(
            DemoModeProbe { seen = $0 }.demoMode(of: model),
        ))
        try show(host) { _ in
            try waitFor { seen != nil }
        }
        return try #require(seen)
    }

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

    @Test func defaultsToTheRealAppOutsideAnyInjection() {
        // The safer default: a view rendered outside the app root (a preview, a
        // widget) reads as the real app, so demo-only affordances stay hidden
        // rather than appearing where there is no demo to leave.
        #expect(!EnvironmentValues().isInDemoMode)
    }

    @Test func readsFalseForAModelOnRealData() throws {
        let model = try WhereModel(
            services: makeServices(),
            preferences: makePreferences(),
            logSystem: .isolated(),
        )
        #expect(try !readValue(from: model))
    }

    @Test func readsTrueOnceTheModelIsInDemoMode() async throws {
        let bootstrap = try ScriptedBootstrap(services: makeServices())
        let model = WhereModel(
            preferences: makePreferences(),
            makeBootstrap: { bootstrap },
            logSystem: .isolated(),
        )
        try await model.activateDemo(model.makeDemoScope())

        #expect(try readValue(from: model))

        await model.deactivateDemo()
        // And back again, so leaving the demo takes the affordances with it.
        #expect(try !readValue(from: model))
    }
}
