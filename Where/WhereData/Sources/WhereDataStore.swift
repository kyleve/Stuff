import Foundation
import WhereCore

public struct WhereDataStore {
    public let yearDataProvider: RepositoryYearDataProvider
    public let evidenceController: EvidenceController
    public let manualEntryController: ManualEntryController
    public let syncController: SyncController
    public let yearExportController: YearExportController
    public let locationRepository: any LocationSampleRepository
    public let trackingStateStore: any TrackingStateStore

    public init(
        yearDataProvider: RepositoryYearDataProvider,
        evidenceController: EvidenceController,
        manualEntryController: ManualEntryController,
        syncController: SyncController,
        yearExportController: YearExportController,
        locationRepository: any LocationSampleRepository,
        trackingStateStore: any TrackingStateStore,
    ) {
        self.yearDataProvider = yearDataProvider
        self.evidenceController = evidenceController
        self.manualEntryController = manualEntryController
        self.syncController = syncController
        self.yearExportController = yearExportController
        self.locationRepository = locationRepository
        self.trackingStateStore = trackingStateStore
    }

    public func makeYearProgressController(
        calendar: Calendar = .current,
    ) -> YearProgressController {
        YearProgressController(
            calendar: calendar,
            yearDataProvider: yearDataProvider,
        )
    }

    public static func makeDefault(
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
    ) -> Self {
        let baseURL = defaultBaseURL(fileManager: fileManager)
        let seedSamples = SampleDataFactory.makeSamples(calendar: calendar)
        let seedManualEntries = SampleDataFactory.makeManualEntries(calendar: calendar)
        let seedEvidenceAttachments = SampleDataFactory.makeEvidenceAttachments(
            manualEntries: seedManualEntries,
            calendar: calendar,
        )
        let locationRepository = FileLocationSampleRepository(
            calendar: calendar,
            fileURL: baseURL.appending(path: "location-samples.json"),
            seedRecords: seedSamples,
        )
        let manualEntryRepository = FileManualLogEntryRepository(
            calendar: calendar,
            fileURL: baseURL.appending(path: "manual-entries.json"),
            seedRecords: seedManualEntries,
        )
        let evidenceRepository = FileEvidenceAttachmentRepository(
            fileURL: baseURL.appending(path: "evidence-index.json"),
            seedRecords: seedEvidenceAttachments,
        )
        let syncCheckpointStore = FileSyncCheckpointStore(
            fileURL: baseURL.appending(path: "sync-checkpoint.json"),
        )
        let trackingStateStore = FileTrackingStateStore(
            fileURL: baseURL.appending(path: "tracking-state.json"),
        )
        let blobStore = FileEvidenceBlobStore(
            baseDirectoryURL: baseURL.appending(path: "evidence"),
        )
        let yearDataProvider = RepositoryYearDataProvider(
            locationRepository: locationRepository,
            manualEntryRepository: manualEntryRepository,
            evidenceRepository: evidenceRepository,
            syncCheckpointStore: syncCheckpointStore,
            trackingStateStore: trackingStateStore,
        )
        let evidenceController = EvidenceController(
            attachmentRepository: evidenceRepository,
            fileStore: blobStore,
        )
        let manualEntryController = ManualEntryController(
            repository: manualEntryRepository,
            evidenceController: evidenceController,
        )
        let yearExportController = YearExportController(
            calendar: calendar,
            yearDataProvider: yearDataProvider,
        )

        return Self(
            yearDataProvider: yearDataProvider,
            evidenceController: evidenceController,
            manualEntryController: manualEntryController,
            syncController: SyncController(store: syncCheckpointStore),
            yearExportController: yearExportController,
            locationRepository: locationRepository,
            trackingStateStore: trackingStateStore,
        )
    }

    static func defaultBaseURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupport.appending(path: "Where")
    }
}
