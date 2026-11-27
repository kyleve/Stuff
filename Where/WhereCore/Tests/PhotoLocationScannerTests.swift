import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct PhotoLocationScannerTests {
    let toronto = Coordinate(latitude: 43.65, longitude: -79.38)

    @Test(arguments: [-301, -300, 0, 300, 301])
    func filtersLibraryTiming(seconds: Int) {
        let capture = Date(timeIntervalSince1970: 1000)
        let observation = PhotoObservation(
            capturedAt: capture,
            addedAt: capture.addingTimeInterval(Double(seconds)),
            coordinate: toronto,
            accuracy: nil,
        )
        #expect((observation != nil) == (abs(seconds) <= 300))
    }

    @Test func rejectsInvalidMetadata() {
        let now = Date()
        #expect(PhotoObservation(capturedAt: nil, addedAt: now, coordinate: toronto, accuracy: 2) ==
            nil)
        #expect(PhotoObservation(capturedAt: now, addedAt: nil, coordinate: toronto, accuracy: 2) ==
            nil)
        #expect(PhotoObservation(capturedAt: now, addedAt: now, coordinate: nil, accuracy: 2) ==
            nil)
        #expect(
            PhotoObservation(capturedAt: now, addedAt: now, coordinate: toronto, accuracy: -1) ==
                nil,
        )
    }

    @Test func scansLimitedLibraryAndDeduplicatesPoints() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Toronto"))
        let day = CalendarDay(year: 2024, month: 2, day: 29)
        let now = day.startOfDay(in: calendar)
        let point = try #require(PhotoObservation(
            capturedAt: now,
            addedAt: now,
            coordinate: toronto,
            accuracy: nil,
        ))
        let future = now.addingTimeInterval(1)
        let futurePoint = try #require(PhotoObservation(
            capturedAt: future,
            addedAt: future,
            coordinate: toronto,
            accuracy: nil,
        ))
        let reader = Reader(observations: [point, point, futurePoint])
        let scan = try await PhotoLocationScanner.scan(
            reader: reader,
            calendar: calendar,
            now: now,
        ) { _, _ in }
        #expect(scan.access == .limited)
        #expect(scan.points.count == 1)
        #expect(scan.points.first?.day == day)
        #expect(scan.points.first?.region.rawValue == "ca-ON")
    }

    @Test func yearBoundaryAndSharedTravelDays() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Toronto"))
        let jan1 = CalendarDay(year: 2026, month: 1, day: 1)
        let boundary = jan1.startOfDay(in: calendar)
        let montreal = Coordinate(latitude: 45.5, longitude: -73.57)
        let outside = Coordinate(latitude: 0, longitude: 0)
        let cases: [(TimeInterval, Coordinate)] = [
            (-1, toronto),
            (0, toronto),
            (20, montreal),
            (30, outside),
        ]
        let observations = try cases.map { offset, coordinate in
            let time = boundary.addingTimeInterval(offset)
            return try #require(PhotoObservation(
                capturedAt: time,
                addedAt: time,
                coordinate: coordinate,
                accuracy: 3,
            ))
        }
        let scan = try await PhotoLocationScanner.scan(
            reader: Reader(observations: observations),
            calendar: calendar,
            now: boundary.addingTimeInterval(30),
        ) { _, _ in }
        #expect(scan.points.count == 3)
        #expect(Set(scan.points.map(\.day)) == [jan1])
        #expect(Set(scan.points.map(\.region.rawValue)) == [
            "ca-ON",
            "ca-QC",
            Region.other.rawValue,
        ])
    }

    @Test func permissionChangesAndCancellationDiscardTheResult() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let denied = Reader(observations: [], initialAccess: .unavailable)
        await #expect(throws: PhotoScanError.unavailable) {
            _ = try await PhotoLocationScanner.scan(
                reader: denied,
                calendar: calendar,
                now: Date(),
            ) { _, _ in
                Issue.record("Denied scan enumerated the library")
            }
        }
        let revoked = Reader(observations: [], finalAccess: .unavailable)
        await #expect(throws: PhotoScanError.accessChanged) {
            _ = try await PhotoLocationScanner.scan(
                reader: revoked,
                calendar: calendar,
                now: Date(),
            ) { _, _ in }
        }
        let canceled = Task {
            try await PhotoLocationScanner.scan(
                reader: Reader(observations: [], cancelOnReadback: true),
                calendar: calendar,
                now: Date(),
            ) { _, _ in }
        }
        await #expect(throws: CancellationError.self) { try await canceled.value }
        let retry = try await PhotoLocationScanner.scan(
            reader: Reader(observations: []),
            calendar: calendar,
            now: Date(),
        ) { _, _ in }
        #expect(retry.points.isEmpty)
    }

    private struct Reader: PhotoLocationReading {
        var observations: [PhotoObservation]
        var initialAccess: PhotoLibraryAccess = .limited
        var finalAccess: PhotoLibraryAccess = .limited
        var cancelOnReadback = false
        func access(requestIfNeeded: Bool) async -> PhotoLibraryAccess {
            if !requestIfNeeded, cancelOnReadback { withUnsafeCurrentTask { $0?.cancel() } }
            return requestIfNeeded ? initialAccess : finalAccess
        }

        func enumerate(
            in _: DateInterval,
            consume: @Sendable ([PhotoObservation], Int, Int) async throws -> Void,
        ) async throws {
            try await consume(observations, observations.count, observations.count)
        }
    }
}
