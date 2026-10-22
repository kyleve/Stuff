import Foundation
import RegionKit
import Testing
import WhereCore

/// A complete recorded cruise window in a minimal backup. Device metadata and
/// geography are invented; callback timing, accuracy, and coordinates come from
/// the transformed recording. No external archive or configuration is required.
enum RecordedFlightArchiveFixture {
    static let samples = RecordedResumedCruiseFlightFixture.samples
    static let now = RecordedResumedCruiseFlightFixture.now
    static let day = CalendarDay(year: 2020, month: 5, day: 1)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Five independently witnessed cruise fixes cross the middle band. Ground
    /// observations stay in the departure and arrival regions. These bands do
    /// not represent the real countries or states on the original route.
    struct Regions: RegionAttributing {
        let loadedRegions: [Region] = [.california, .newYork, .canada]

        func region(at coordinate: Coordinate) -> Region {
            if coordinate.longitude > -40 { return .california }
            if (-64 ... -61).contains(coordinate.longitude) { return .canada }
            return .newYork
        }

        func distanceToBoundary(of _: Region, from _: Coordinate) -> Double? {
            nil
        }
    }

    static func makeArchiveFile() throws -> URL {
        let first = try #require(samples.min { $0.timestamp < $1.timestamp })
        let deviceID = try #require(first.recordingDeviceID)
        let regions = Regions().loadedRegions
        return try BackupService().makeArchiveFile(
            samples: samples,
            evidence: [],
            manualDays: [],
            dismissedIssues: [],
            trackedRegions: regions,
            primaryRegions: regions.enumerated().map {
                PrimaryRegion(region: $0.element, appearance: nil, order: $0.offset)
            },
            recordingDeviceProfiles: [RecordingDeviceProfile(
                id: deviceID,
                systemName: "Recorded fixture phone",
                kind: .phone,
                registeredAt: first.timestamp,
                registrationGenerationID: .initial,
            )],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
            blobs: [:],
            exportedAt: now,
            archiveName: "recorded-flight.zip",
        )
    }
}
