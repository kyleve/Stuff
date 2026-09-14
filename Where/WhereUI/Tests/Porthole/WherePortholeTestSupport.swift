import Foundation
import PortholeRuntime
import PortholeUI
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct WherePortholeTestFixture {
    let preferences: WherePreferences
    let registry: PortholeRegistry
    let controller: WherePortholeController
    let directory: URL
    let screenshots = WherePortholeScreenshotProbe()

    init(enabled: Bool) {
        preferences = makePreferences()
        preferences.isPortholeEnabled = enabled
        directory = URL.temporaryDirectory.appending(
            path: "WherePorthole-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10000)
        controller = WherePortholeController(
            preferences: preferences,
            registry: registry,
            investigationURL: directory
                .appending(path: "investigation.json"),
            screenshots: screenshots,
        )
    }

    var token: PortholeScopeToken? {
        if case let .ready(token) = controller.state { token } else { nil }
    }

    func screen(
        title: String,
        depth: Int,
        capture: @escaping @MainActor () throws -> PortholeValue,
    ) -> WherePortholeController
        .Screen
    {
        .init(
            id: UUID(),
            owningScope: nil,
            depth: depth,
            title: title,
            source: .init(path: "Fixture.swift", line: 7),
            capture: capture,
            roots: [],
        )
    }

    func makeScope() throws -> WhereScope {
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return WhereScope.fake(services: services, preferences: preferences, logSystem: .isolated())
    }

    func removeFiles() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove the isolated investigation fixture: \(error)") }
    }
}

@MainActor final class WherePortholeTestRoot {}

actor WherePortholeInstallerProbe {
    private(set) var count = 0
    func installed() {
        count += 1
    }
}

@MainActor final class WherePortholeScreenshotProbe: PortholeScreenshotCapturing {
    var result: Result<Data, PortholeError> = .success(Data("application image".utf8))
    private(set) var captures = 0
    func capturePNG() throws -> Data {
        captures += 1; return try result.get()
    }
}

actor WherePortholeInstallationGate {
    private(set) var hasArrived = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func arrive() async {
        hasArrived = true
        if !released { await withCheckedContinuation { continuation = $0 } }
    }

    func release() {
        released = true; continuation?.resume(); continuation = nil
    }
}

/// A synthetic Reno fix within California's drift threshold. Seed before services subscribe to
/// changes so a delayed setup notification cannot invalidate the scanner during the assertion.
@MainActor
struct WherePortholeDriftFixture {
    let store: SwiftDataStore
    let scope: WhereScope
    let day: CalendarDay
    let sample: LocationSample
    let thresholdMeters: Double

    static func make(preferences: WherePreferences) async throws -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let day = CalendarDay(year: 2026, month: 3, day: 1)
        let now = day.startOfDay(in: calendar).addingTimeInterval(12 * 3600)
        let sample = LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 39.5296, longitude: -119.8138),
            horizontalAccuracy: 20,
            source: .gpsVisit,
        )
        let thresholdMeters = 50000.0
        preferences.driftThresholdMeters = Int(thresholdMeters)
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.add(sample: sample)
            try await store.setIssueDismissed(true, id: .borderDrift(day: day))
        }
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            attributor: RegionAttributor.shared,
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        return Self(
            store: store,
            scope: WhereScope.fake(
                services: services,
                preferences: preferences,
                logSystem: .isolated(),
            ),
            day: day,
            sample: sample,
            thresholdMeters: thresholdMeters,
        )
    }
}
