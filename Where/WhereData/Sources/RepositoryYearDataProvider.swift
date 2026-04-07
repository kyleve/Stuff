import Foundation
import WhereCore

public actor RepositoryYearDataProvider: YearDataProviding {
    private let locationRepository: any LocationSampleRepository
    private let manualEntryRepository: any ManualLogEntryRepository
    private let evidenceRepository: any EvidenceAttachmentRepository
    private let syncCheckpointStore: any SyncCheckpointStore
    private let trackingStateStore: (any TrackingStateStore)?

    public init(
        locationRepository: any LocationSampleRepository,
        manualEntryRepository: any ManualLogEntryRepository,
        evidenceRepository: any EvidenceAttachmentRepository,
        syncCheckpointStore: any SyncCheckpointStore,
        trackingStateStore: (any TrackingStateStore)? = nil,
    ) {
        self.locationRepository = locationRepository
        self.manualEntryRepository = manualEntryRepository
        self.evidenceRepository = evidenceRepository
        self.syncCheckpointStore = syncCheckpointStore
        self.trackingStateStore = trackingStateStore
    }

    public func availableYears() async -> [Int] {
        let locationYears = await locationRepository.availableYears()
        let manualYears = await manualEntryRepository.availableYears()
        return Array(Set(locationYears).union(manualYears)).sorted()
    }

    public func bundle(for year: Int) async -> YearDataBundle {
        let locationSamples = await locationRepository.samples(in: year)
        let manualEntries = await manualEntryRepository.entries(in: year)
        let evidenceAttachments = await evidenceRepository.attachments(for: manualEntries.map(\.id))
        let syncCheckpoint = await syncCheckpointStore.checkpoint()
        let trackingState = await trackingStateStore?.load()

        return YearDataBundle(
            year: year,
            locationSamples: locationSamples,
            manualEntries: manualEntries,
            evidenceAttachments: evidenceAttachments,
            syncCheckpoint: syncCheckpoint,
            trackingState: trackingState,
        )
    }
}
