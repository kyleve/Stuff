import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct OnboardingPhotoImportModelTests {
    private struct ScriptedLibrary: PhotoLocationLibrary {
        let authorization: PhotoLibraryAuthorization
        let requestedAuthorization: PhotoLibraryAuthorization
        let values: [PhotoLocationAsset]
        var fails = false

        func authorizationStatus() async -> PhotoLibraryAuthorization {
            authorization
        }

        func requestAuthorization() async -> PhotoLibraryAuthorization {
            requestedAuthorization
        }

        func assets(in _: DateInterval) async throws -> [PhotoLocationAsset] {
            if fails { throw Failure.read }
            return values
        }
    }

    private enum Failure: Error {
        case read
    }

    @Test func scanBuildsAProvisionalDraft() async throws {
        let capturedAt = try #require(ISO8601DateFormatter().date(from: "2026-02-10T12:00:00Z"))
        let model = OnboardingPhotoImportModel()
        model.beginScan()

        try await model.scan(
            library: ScriptedLibrary(
                authorization: .authorized,
                requestedAuthorization: .authorized,
                values: [asset(capturedAt: capturedAt)],
            ),
            year: 2026,
            regions: [.california],
            calendar: calendar,
            now: #require(ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")),
        )

        let draft = try #require(model.draft)
        #expect(draft.samples.count == 1)
        #expect(model.isLimited == false)
    }

    @Test func limitedEmptyScanStaysHonest() async throws {
        let model = OnboardingPhotoImportModel()
        model.beginScan()

        try await model.scan(
            library: ScriptedLibrary(
                authorization: .notDetermined,
                requestedAuthorization: .limited,
                values: [],
            ),
            year: 2026,
            regions: [.california],
            calendar: calendar,
            now: #require(ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")),
        )

        guard case let .empty(isLimited) = model.activity else {
            Issue.record("Expected an empty result")
            return
        }
        #expect(isLimited)
    }

    @Test func deniedScanBecomesBlockedWithoutReading() async throws {
        let model = OnboardingPhotoImportModel()
        model.beginScan()

        try await model.scan(
            library: ScriptedLibrary(
                authorization: .denied,
                requestedAuthorization: .denied,
                values: [asset(capturedAt: .now)],
                fails: true,
            ),
            year: 2026,
            regions: [.california],
            calendar: calendar,
            now: #require(ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")),
        )

        guard case .blocked(.denied) = model.activity else {
            Issue.record("Expected denied authorization to block the scan")
            return
        }
        #expect(model.errorMessage == nil)
    }

    @Test func cancelledImportReturnsToTheApprovedDraftWithoutAnError() throws {
        let capturedAt = try #require(ISO8601DateFormatter().date(from: "2026-02-10T12:00:00Z"))
        let model = OnboardingPhotoImportModel()
        let draft = PhotoHistoryDraft(
            year: 2026,
            calendar: calendar,
            samples: [LocationSample(
                timestamp: capturedAt,
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 12,
                source: .photo,
            )],
            regions: [.california],
        )
        model.activity = .ready(draft, isLimited: false)

        _ = model.beginImport()
        model.importCancelled()

        #expect(model.draft?.samples.count == 1)
        #expect(model.errorMessage == nil)
        guard case .ready = model.activity else {
            Issue.record("Expected cancellation to restore the ready state")
            return
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func asset(capturedAt: Date) -> PhotoLocationAsset {
        PhotoLocationAsset(
            capturedAt: capturedAt,
            addedAt: capturedAt,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 12,
            source: .userLibrary,
            isHidden: false,
        )
    }
}
