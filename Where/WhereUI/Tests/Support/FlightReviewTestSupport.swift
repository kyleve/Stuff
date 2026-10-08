import Foundation
import RegionKit
@_spi(Testing) import WhereCore

/// Public airport coordinates and synthetic timing; contains no exported user GPS data.
enum FlightReviewTestSupport {
    struct Fix {
        let hour: Double
        let coordinate: Coordinate
    }

    static func flight(recordingSource: FlightAssessment.RecordingSource) -> FlightAssessment {
        FlightAssessment(
            id: .init(recordingSource: recordingSource, departureSampleID: UUID()),
            startedAt: date(hour: 12),
            lastObservationAt: date(hour: 16.5),
            lastFlightAt: date(hour: 16.5),
            airborneSampleIDs: [],
            groundSampleIDs: [],
            peakSpeedKMH: 800,
            progress: .awaitingArrival,
            inferredEndpoints: [],
        )
    }

    static let destination = Coordinate(latitude: 37.6213, longitude: -122.3790)

    static func date(hour: Double) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 15,
            hour: Int(hour),
            minute: Int(((hour - Double(Int(hour))) * 60).rounded()),
        ))!
    }

    static func services(store: TestStore, now: Date) -> WhereServices {
        WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
    }

    static func seed(into store: TestStore, includeArrival: Bool) async throws {
        let origin = Coordinate(latitude: 40.6413, longitude: -73.7781)
        var fixes = [
            Fix(hour: 8, coordinate: origin),
            Fix(hour: 8.5, coordinate: origin),
            Fix(hour: 12, coordinate: origin),
            Fix(hour: 13.5, coordinate: Coordinate(latitude: 40.29, longitude: -90.39)),
            Fix(hour: 15, coordinate: Coordinate(latitude: 39.53, longitude: -106.16)),
            Fix(hour: 16.5, coordinate: Coordinate(latitude: 38.68, longitude: -116.90)),
        ]
        if includeArrival {
            fixes.append(contentsOf: [
                Fix(hour: 17.5, coordinate: destination),
                Fix(hour: 17.5 + 5.0 / 60, coordinate: destination),
                Fix(hour: 17.5 + 10.0 / 60, coordinate: destination),
            ])
        }
        let samples = fixes.map { fix in
            LocationSample(
                timestamp: date(hour: fix.hour),
                coordinate: fix.coordinate,
                horizontalAccuracy: 20,
                source: .gpsSignificantChange,
                recordingDeviceID: CurrentRecordingDevice.preview.id,
            )
        }
        try await store.perform {
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
    }

    static func seedMixedFlights(into store: TestStore) async throws {
        try await seed(into: store, includeArrival: true)
        let samples = try await store.allSamples()
        let otherDevice = RecordingDeviceID(rawValue: UUID())
        let pendingSamples = samples.filter { $0.timestamp <= date(hour: 16.5) }.map { sample in
            LocationSample(
                id: UUID(),
                timestamp: sample.timestamp,
                coordinate: sample.coordinate,
                horizontalAccuracy: sample.horizontalAccuracy,
                source: sample.source,
                recordingDeviceID: otherDevice,
            )
        }
        try await store.perform {
            for sample in pendingSamples {
                try await store.add(sample: sample)
            }
        }
    }
}
