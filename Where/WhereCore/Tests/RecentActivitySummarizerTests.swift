import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers the 24h windowing, region attribution, empty-window handling, and
/// error propagation of `RecentActivitySummarizer` against a scripted generator
/// (the on-device Foundation Models path is device-only and not unit-tested).
struct RecentActivitySummarizerTests {
    private enum StubError: Error { case boom }

    /// Scripted `ActivitySummaryGenerating` that records the input it was handed
    /// and returns a canned outcome, so tests can assert both the summary and
    /// what the summarizer fed the model.
    private actor StubGenerator: ActivitySummaryGenerating {
        enum Outcome {
            case text(String)
            case unavailable(ActivitySummaryUnavailableReason)
            case failure
        }

        private let outcome: Outcome
        private(set) var receivedInput: RecentActivityInput?

        init(_ outcome: Outcome) {
            self.outcome = outcome
        }

        func summarize(_ input: RecentActivityInput) async throws -> String {
            receivedInput = input
            switch outcome {
                case let .text(text): return text
                case let .unavailable(reason): throw ActivitySummaryUnavailableError(reason: reason)
                case .failure: throw StubError.boom
            }
        }
    }

    private static let now = WhereCoreTestSupport.iso("2026-05-02T12:00:00-07:00")

    private static func makeSummarizer(
        store: SwiftDataStore,
        generator: StubGenerator,
    ) -> RecentActivitySummarizer {
        RecentActivitySummarizer(
            store: store,
            attributor: .shared,
            generator: generator,
            now: { now },
        )
    }

    private static func californiaSample(at date: Date) -> LocationSample {
        LocationSample(
            timestamp: date,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }

    @Test func emptyWindowReturnsEmptyWithoutCallingGenerator() async throws {
        let store = try SwiftDataStore.inMemory()
        let generator = StubGenerator(.text("unused"))
        let summarizer = Self.makeSummarizer(store: store, generator: generator)

        #expect(try await summarizer.summary() == .empty)
        #expect(await generator.receivedInput == nil)
    }

    @Test func summarizesOnlyStopsInsideThe24hWindow() async throws {
        let store = try SwiftDataStore.inMemory()
        // One reading an hour ago (in window) and one 30 hours ago (out of it).
        let inWindow = Self.californiaSample(at: Self.now.addingTimeInterval(-60 * 60))
        let outOfWindow = Self.californiaSample(at: Self.now.addingTimeInterval(-30 * 60 * 60))
        try await store.perform {
            try await store.add(sample: inWindow)
            try await store.add(sample: outOfWindow)
        }
        let generator = StubGenerator(.text("You were in California."))
        let summarizer = Self.makeSummarizer(store: store, generator: generator)

        #expect(try await summarizer.summary() == .summary("You were in California."))
        let input = try #require(await generator.receivedInput)
        #expect(input.stops.count == 1)
        #expect(input.stops.first?.region == .california)
        #expect(input.stops.first?.timestamp == inWindow.timestamp)
    }

    @Test func unavailableModelPropagatesTypedError() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-3600)))
        }
        let generator = StubGenerator(.unavailable(.appleIntelligenceNotEnabled))
        let summarizer = Self.makeSummarizer(store: store, generator: generator)

        await #expect(
            throws: ActivitySummaryUnavailableError(reason: .appleIntelligenceNotEnabled),
        ) {
            _ = try await summarizer.summary()
        }
    }

    @Test func generatorFailurePropagates() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-3600)))
        }
        let generator = StubGenerator(.failure)
        let summarizer = Self.makeSummarizer(store: store, generator: generator)

        await #expect(throws: StubError.self) {
            _ = try await summarizer.summary()
        }
    }
}
