import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

/// Covers `RecentActivityModel`'s mapping of the summarizer's output (and its
/// failures) to a `LoadState`, against a scripted generator and an in-memory
/// store.
@MainActor
struct RecentActivityModelTests {
    private enum StubError: Error { case boom }

    /// Scripted `ActivitySummaryGenerating`. Immutable, so `Sendable`.
    private struct StubGenerator: ActivitySummaryGenerating {
        enum Outcome {
            case text(String)
            case unavailable(ActivitySummaryUnavailableReason)
            case failure
        }

        let outcome: Outcome

        func summarize(_: RecentActivityInput) async throws -> String {
            switch outcome {
                case let .text(text): return text
                case let .unavailable(reason): throw ActivitySummaryUnavailableError(reason: reason)
                case .failure: throw StubError.boom
            }
        }
    }

    /// `nonisolated` so the `@Sendable` `now:` closure in `makeServices` can
    /// capture it without hopping off this `@MainActor` suite; `Date` is `Sendable`.
    private nonisolated static let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 5, day: 2, hour: 12),
    )!

    private func makeServices(store: TestStore, generator: StubGenerator) -> WhereServices {
        WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            activitySummaryGenerator: generator,
            now: { Self.now },
        )
    }

    private func seedRecentSample(_ services: WhereServices) async throws {
        try await services.journal.ingest(LocationSample(
            timestamp: Self.now.addingTimeInterval(-3600),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        ))
    }

    @Test func loadWithNoSamplesIsEmpty() async throws {
        let store = try TestStore()
        let services = makeServices(
            store: store,
            generator: StubGenerator(outcome: .text("unused")),
        )
        let model = RecentActivityModel(services: services)

        await model.load()

        #expect(model.loadState == .empty)
    }

    @Test func loadWithSamplesShowsGeneratedSummary() async throws {
        let store = try TestStore()
        let services = makeServices(
            store: store,
            generator: StubGenerator(outcome: .text("You spent the day in California.")),
        )
        try await seedRecentSample(services)
        let model = RecentActivityModel(services: services)

        await model.load()

        #expect(model.loadState == .loaded("You spent the day in California."))
    }

    @Test func loadMapsUnavailableModelToUnavailableState() async throws {
        let store = try TestStore()
        let services = makeServices(
            store: store,
            generator: StubGenerator(outcome: .unavailable(.appleIntelligenceNotEnabled)),
        )
        try await seedRecentSample(services)
        let model = RecentActivityModel(services: services)

        await model.load()

        #expect(model.loadState == .unavailable(.appleIntelligenceNotEnabled))
    }

    @Test func loadMapsGenerationFailureToFailedState() async throws {
        let store = try TestStore()
        let services = makeServices(store: store, generator: StubGenerator(outcome: .failure))
        try await seedRecentSample(services)
        let model = RecentActivityModel(services: services)

        await model.load()

        guard case .failed = model.loadState else {
            Issue.record("Expected .failed, got \(model.loadState)")
            return
        }
    }

    @Test func changingWindowRegeneratesForTheNewRange() async throws {
        let store = try TestStore()
        let services = makeServices(
            store: store,
            generator: StubGenerator(outcome: .text("You were around.")),
        )
        // A reading three days ago is outside `.day` but inside `.week`.
        try await services.journal.ingest(LocationSample(
            timestamp: Self.now.addingTimeInterval(-3 * 24 * 3600),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        ))
        let model = RecentActivityModel(services: services)

        await model.load()
        #expect(model.loadState == .empty)

        model.window = .week
        await model.load()
        #expect(model.loadState == .loaded("You were around."))
    }
}
