import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct PhotoHistoryPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func acceptsOnlyLikelyCurrentYearDeviceCaptures() async throws {
        let capture = try #require(ISO8601DateFormatter().date(from: "2026-03-10T12:00:00Z"))
        let valid = asset(capturedAt: capture, addedAt: capture.addingTimeInterval(300))
        let tooLate = asset(capturedAt: capture, addedAt: capture.addingTimeInterval(301))
        let shared = asset(capturedAt: capture, addedAt: capture, source: .cloudShared)
        let hidden = asset(capturedAt: capture, addedAt: capture, isHidden: true)
        let invalidAccuracy = asset(capturedAt: capture, addedAt: capture, accuracy: -1)
        let old = try asset(
            capturedAt: #require(ISO8601DateFormatter().date(from: "2025-12-31T23:59:59Z")),
            addedAt: capture,
        )

        let draft = try await PhotoHistoryPlanner().makeDraft(
            assets: [valid, tooLate, shared, hidden, invalidAccuracy, old],
            year: 2026,
            regions: [.california],
            calendar: calendar,
            now: #require(ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")),
        )

        #expect(draft.samples.count == 1)
        #expect(draft.samples.first?.source == .photo)
    }

    @Test func duplicateMetadataProducesOneStableSample() async throws {
        let capture = try #require(ISO8601DateFormatter().date(from: "2026-03-10T12:00:00Z"))
        let input = asset(capturedAt: capture, addedAt: capture)
        let planner = PhotoHistoryPlanner()
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z"))
        let first = try await planner.makeDraft(
            assets: [input, input],
            year: 2026,
            regions: [.california],
            calendar: calendar,
            now: now,
        )
        let second = try await planner.makeDraft(
            assets: [input],
            year: 2026,
            regions: [.california],
            calendar: calendar,
            now: now,
        )

        #expect(first.samples.count == 1)
        #expect(first.samples.first?.id == second.samples.first?.id)
    }

    private func asset(
        capturedAt: Date?,
        addedAt: Date?,
        source: PhotoAssetLibrarySource = .userLibrary,
        isHidden: Bool = false,
        accuracy: Double = 12,
    ) -> PhotoLocationAsset {
        PhotoLocationAsset(
            capturedAt: capturedAt,
            addedAt: addedAt,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: accuracy,
            source: source,
            isHidden: isHidden,
        )
    }
}

struct PhotoHistoryDraftTests {
    @Test func exclusionsAndCorrectionsRebuildPreviewAndImport() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDate = try #require(ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))
        let secondDate = try #require(ISO8601DateFormatter().date(from: "2026-01-02T12:00:00Z"))
        var draft = PhotoHistoryDraft(
            year: 2026,
            calendar: calendar,
            samples: [
                LocationSample(
                    timestamp: firstDate,
                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                    horizontalAccuracy: 10,
                    source: .photo,
                ),
                LocationSample(
                    timestamp: secondDate,
                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                    horizontalAccuracy: 10,
                    source: .photo,
                ),
            ],
            regions: [.california, .newYork],
        )
        let first = CalendarDay(from: firstDate, in: calendar)
        let second = CalendarDay(from: secondDate, in: calendar)

        draft.setDecision(.corrected([.newYork]), from: first, through: second)
        draft.setDecision(.excluded, from: first, through: first)

        #expect(draft.report.days == [
            DayPresence(day: second, regions: [.newYork], isAuthoritative: false, audit: nil),
        ])
        #expect(draft.approvedImport.samples.map(\.timestamp) == [secondDate])
        #expect(draft.approvedImport.corrections.map(\.day) == [second])
        #expect(draft.decision(for: first) == .excluded)
        #expect(draft.decision(for: second) == .corrected([.newYork]))
    }

    @Test func includedDecisionResetsAnEdit() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))
        let day = CalendarDay(from: date, in: calendar)
        var draft = PhotoHistoryDraft(
            year: 2026,
            calendar: calendar,
            samples: [LocationSample(
                timestamp: date,
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 10,
                source: .photo,
            )],
            regions: [.california],
        )

        draft.setDecision(.excluded, from: day, through: day)
        draft.setDecision(.included, from: day, through: day)

        #expect(draft.decision(for: day) == .included)
        #expect(draft.approvedImport.samples.count == 1)
    }

    @Test func restoringExclusionsPreservesOtherCorrections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDate = try #require(ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))
        let secondDate = try #require(ISO8601DateFormatter().date(from: "2026-01-02T12:00:00Z"))
        let first = CalendarDay(from: firstDate, in: calendar)
        let second = CalendarDay(from: secondDate, in: calendar)
        var draft = PhotoHistoryDraft(
            year: 2026,
            calendar: calendar,
            samples: [firstDate, secondDate].map {
                LocationSample(
                    timestamp: $0,
                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                    horizontalAccuracy: 10,
                    source: .photo,
                )
            },
            regions: [.california, .newYork],
        )
        draft.setDecision(.excluded, from: first, through: first)
        draft.setDecision(.corrected([.newYork]), from: second, through: second)

        draft.restoreExcludedDays()

        #expect(draft.hasExcludedDays == false)
        #expect(draft.decision(for: first) == .included)
        #expect(draft.decision(for: second) == .corrected([.newYork]))
    }
}
