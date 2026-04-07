import Foundation
import WhereCore

public actor SampleYearDataProvider: YearDataProviding {
    private let calendar: Calendar
    private let sampleData: [LocationSample]
    private let manualEntries: [ManualLogEntry]
    private let evidenceAttachments: [EvidenceAttachment]
    private let syncCheckpoint: SyncCheckpoint
    private let trackingState: TrackingState

    public init(
        calendar: Calendar = .current,
        sampleData: [LocationSample]? = nil,
        manualEntries: [ManualLogEntry]? = nil,
        evidenceAttachments: [EvidenceAttachment]? = nil,
        syncCheckpoint: SyncCheckpoint = .init(state: .idle),
        trackingState: TrackingState? = nil,
    ) {
        let resolvedSampleData = sampleData ?? SampleDataFactory.makeSamples(calendar: calendar)
        let resolvedManualEntries = manualEntries ?? SampleDataFactory.makeManualEntries(calendar: calendar)
        let resolvedEvidenceAttachments = evidenceAttachments
            ?? SampleDataFactory.makeEvidenceAttachments(
                manualEntries: resolvedManualEntries,
                calendar: calendar,
            )
        let currentDate = Date()
        let resolvedTrackingState = trackingState ?? TrackingState(
            authorizationStatus: .authorizedAlways,
            lastWakeEventAt: currentDate,
            lastRecordedSampleAt: currentDate,
            lastWakeReason: .appLaunch,
            isMonitoringActive: true,
        )

        self.calendar = calendar
        self.sampleData = resolvedSampleData
        self.manualEntries = resolvedManualEntries
        self.evidenceAttachments = resolvedEvidenceAttachments
        self.syncCheckpoint = syncCheckpoint
        self.trackingState = resolvedTrackingState
    }

    public func availableYears() async -> [Int] {
        let sampleYears = sampleData.map { calendar.component(.year, from: $0.timestamp) }
        let manualYears = manualEntries.map { calendar.component(.year, from: $0.timestamp) }
        return Array(Set(sampleYears).union(manualYears)).sorted()
    }

    public func bundle(for year: Int) async -> YearDataBundle {
        let yearManualEntries = manualEntries
            .filter { calendar.component(.year, from: $0.timestamp) == year }
            .sorted { $0.timestamp < $1.timestamp }
        let manualEntryIDs = Set(yearManualEntries.map(\.id))

        return YearDataBundle(
            year: year,
            locationSamples: sampleData
                .filter { calendar.component(.year, from: $0.timestamp) == year }
                .sorted { $0.timestamp < $1.timestamp },
            manualEntries: yearManualEntries,
            evidenceAttachments: evidenceAttachments
                .filter { manualEntryIDs.contains($0.manualEntryID) }
                .sorted { $0.createdAt < $1.createdAt },
            syncCheckpoint: syncCheckpoint,
            trackingState: trackingState,
        )
    }
}

enum SampleDataFactory {
    static func makeSamples(calendar: Calendar) -> [LocationSample] {
        let year = calendar.component(.year, from: Date())

        return [
            makeSample(year: year, month: 1, day: 4, hour: 9, jurisdiction: .california, calendar: calendar),
            makeSample(year: year, month: 1, day: 4, hour: 20, jurisdiction: .newYork, calendar: calendar),
            makeSample(year: year, month: 2, day: 10, hour: 8, jurisdiction: .california, calendar: calendar),
            makeSample(year: year, month: 2, day: 11, hour: 8, jurisdiction: .california, calendar: calendar),
            makeSample(year: year, month: 2, day: 12, hour: 8, jurisdiction: .unknown, calendar: calendar),
            makeSample(year: year, month: 2, day: 13, hour: 8, jurisdiction: .newYork, calendar: calendar),
        ]
    }

    static func makeManualEntries(calendar: Calendar) -> [ManualLogEntry] {
        let year = calendar.component(.year, from: Date())

        return [
            ManualLogEntry(
                timestamp: makeDate(year: year, month: 2, day: 12, hour: 12, calendar: calendar),
                jurisdiction: .newYork,
                note: "Attached ticket for overnight travel",
                kind: .correction,
            ),
            ManualLogEntry(
                timestamp: makeDate(year: year, month: 1, day: 4, hour: 21, calendar: calendar),
                jurisdiction: .california,
                note: "Added airport evidence",
                kind: .supplemental,
            ),
        ]
    }

    static func makeEvidenceAttachments(
        manualEntries: [ManualLogEntry],
        calendar: Calendar,
    ) -> [EvidenceAttachment] {
        guard
            manualEntries.count >= 2
        else {
            return []
        }

        return [
            EvidenceAttachment(
                manualEntryID: manualEntries[0].id,
                originalFilename: "overnight-train-ticket.pdf",
                contentType: "application/pdf",
                byteCount: 48000,
                createdAt: makeDate(
                    year: calendar.component(.year, from: manualEntries[0].timestamp),
                    month: 2,
                    day: 12,
                    hour: 12,
                    calendar: calendar,
                ),
            ),
            EvidenceAttachment(
                manualEntryID: manualEntries[1].id,
                originalFilename: "airport-receipt.jpg",
                contentType: "image/jpeg",
                byteCount: 8300,
                createdAt: makeDate(
                    year: calendar.component(.year, from: manualEntries[1].timestamp),
                    month: 1,
                    day: 4,
                    hour: 21,
                    calendar: calendar,
                ),
            ),
        ]
    }

    private static func makeSample(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        jurisdiction: TaxJurisdiction,
        calendar: Calendar,
    ) -> LocationSample {
        let components = DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day,
            hour: hour,
        )

        return LocationSample(
            timestamp: components.date ?? Date(),
            jurisdiction: jurisdiction,
        )
    }

    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar,
    ) -> Date {
        DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day,
            hour: hour,
        )
        .date ?? Date()
    }
}
