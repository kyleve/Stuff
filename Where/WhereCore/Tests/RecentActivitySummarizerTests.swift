import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers windowing (rolling and wider ranges), region attribution, the
/// collapse-and-cap of readings into dwell segments, empty-window handling, and
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
        segmentLimit: Int = RecentActivitySummarizer.defaultSegmentLimit,
    ) -> RecentActivitySummarizer {
        RecentActivitySummarizer(
            store: store,
            attributor: .shared,
            generator: generator,
            calendar: .current,
            now: { now },
            segmentLimit: segmentLimit,
        )
    }

    private static func californiaSample(at date: Date) -> LocationSample {
        sample(at: date, latitude: 37.7749, longitude: -122.4194)
    }

    private static func newYorkSample(at date: Date) -> LocationSample {
        sample(at: date, latitude: 40.7128, longitude: -74.0060)
    }

    private static func sample(
        at date: Date,
        latitude: Double,
        longitude: Double,
    ) -> LocationSample {
        LocationSample(
            timestamp: date,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }

    @Test func emptyWindowReturnsEmptyWithoutCallingGenerator() async throws {
        let store = try SwiftDataStore.inMemory()
        let generator = StubGenerator(.text("unused"))
        let summarizer = Self.makeSummarizer(store: store, generator: generator)

        #expect(try await summarizer.summary(for: .day) == .empty)
        #expect(await generator.receivedInput == nil)
    }

    @Test func summarizesOnlyReadingsInsideThe24hWindow() async throws {
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

        #expect(try await summarizer.summary(for: .day) == .summary("You were in California."))
        let input = try #require(await generator.receivedInput)
        #expect(input.segments.count == 1)
        #expect(input.segments.first?.region == .california)
        // A lone reading is a zero-length segment at its own timestamp.
        #expect(input.segments.first?.start == inWindow.timestamp)
        #expect(input.segments.first?.end == inWindow.timestamp)
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
            _ = try await summarizer.summary(for: .day)
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
            _ = try await summarizer.summary(for: .day)
        }
    }

    @Test func collapsesConsecutiveSameRegionReadingsToOneSegment() async throws {
        let store = try SwiftDataStore.inMemory()
        // Three readings in the same region within the window collapse to one
        // segment spanning the run's first to last reading (its dwell time).
        try await store.perform {
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-3 * 3600)))
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-2 * 3600)))
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-3600)))
        }
        let generator = StubGenerator(.text("summary"))
        let summarizer = Self.makeSummarizer(store: store, generator: generator)

        _ = try await summarizer.summary(for: .day)
        let input = try #require(await generator.receivedInput)
        #expect(input.segments.count == 1)
        #expect(input.segments.first?.start == Self.now.addingTimeInterval(-3 * 3600))
        #expect(input.segments.first?.end == Self.now.addingTimeInterval(-3600))
    }

    @Test func capsSegmentsToTheMostRecentWithinTheLimit() async throws {
        let store = try SwiftDataStore.inMemory()
        // Five alternating-region readings (so none collapse); a limit of 3
        // keeps only the three most recent segments.
        try await store.perform {
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-5 * 3600)))
            try await store
                .add(sample: Self.newYorkSample(at: Self.now.addingTimeInterval(-4 * 3600)))
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-3 * 3600)))
            try await store
                .add(sample: Self.newYorkSample(at: Self.now.addingTimeInterval(-2 * 3600)))
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-3600)))
        }
        let generator = StubGenerator(.text("summary"))
        let summarizer = Self.makeSummarizer(store: store, generator: generator, segmentLimit: 3)

        _ = try await summarizer.summary(for: .day)
        let input = try #require(await generator.receivedInput)
        #expect(input.segments.count == 3)
        #expect(input.segments.first?.start == Self.now.addingTimeInterval(-3 * 3600))
        #expect(input.segments.last?.start == Self.now.addingTimeInterval(-3600))
    }

    @Test func widerWindowIncludesReadingsOutsideThe24hWindow() async throws {
        let store = try SwiftDataStore.inMemory()
        // A reading three days ago is outside `.day` but inside `.week`.
        try await store.perform {
            try await store
                .add(sample: Self.californiaSample(at: Self.now.addingTimeInterval(-3 * 24 * 3600)))
        }
        let generator = StubGenerator(.text("You were in California."))
        let summarizer = Self.makeSummarizer(store: store, generator: generator)

        #expect(try await summarizer.summary(for: .day) == .empty)
        #expect(try await summarizer.summary(for: .week) == .summary("You were in California."))
    }
}
