import Foundation
import Testing
@testable import WhereCore

/// Shared converter output is bundled, so CI validates the Ruby/Swift wire contract without a
/// checkout.
enum RecordingBackupTestSupport {
    private final class BundleAnchor {}
    static let policy = DataCompatibilityPolicy(
        current: .init(major: 1, minor: 0, patch: 0),
        supportedMajors: [1],
    )

    enum Archive: String { case converted, historical, places, epochBoundary = "epoch-boundary" }

    static func convertedArchive(_ archive: Archive = .converted) throws -> BackupArchive {
        let url = try #require(Bundle(for: BundleAnchor.self).url(
            forResource: archive.rawValue,
            withExtension: "json",
            subdirectory: "RecordingBackup",
        ))
        return try BackupService.decodeManifest(Data(contentsOf: url), policy: policy)
    }

    static func controls() throws -> [VersionedHistoryRecord] {
        let context = try RecordingCalendarContext(timeZone: .gmt, secondsFromGMT: 0)
        let controls: [RecordingControl] = try [
            .source(RecordingAssessmentTestSupport.decision(11)),
            .ignore(RecordingControlsTestSupport.ignore(12)),
            .place(RecordingControlsTestSupport.place(13, end: nil)),
            .calendar(RecordingControlsTestSupport.calendar(14, action: .establish(context))),
        ]
        return try controls.map { try RecordingControlCodec.encode($0, generationID: .initial) }
    }

    static func zip(samples: [LocationSample], controls: [VersionedHistoryRecord]) throws -> URL {
        try BackupService(policy: policy).makeArchiveFile(
            requiredDataMajor: 1,
            versionedHistoryRecords: controls,
            samples: samples,
            evidence: [],
            manualDays: [],
            recordingDeviceProfiles: [],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
            blobs: [:],
        )
    }
}
