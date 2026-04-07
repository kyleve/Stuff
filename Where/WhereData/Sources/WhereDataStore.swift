import Foundation
import WhereCore

public struct WhereDataStore {
    public let yearDataProvider: RepositoryYearDataProvider
    public let evidenceController: EvidenceController
    public let manualEntryController: ManualEntryController
    public let manualDataImportController: ManualDataImportController
    public let resetController: ResetController
    public let syncController: SyncController
    public let yearExportController: YearExportController
    public let locationRepository: any LocationSampleRepository
    public let trackingStateStore: any TrackingStateStore

    public init(
        yearDataProvider: RepositoryYearDataProvider,
        evidenceController: EvidenceController,
        manualEntryController: ManualEntryController,
        manualDataImportController: ManualDataImportController,
        resetController: ResetController,
        syncController: SyncController,
        yearExportController: YearExportController,
        locationRepository: any LocationSampleRepository,
        trackingStateStore: any TrackingStateStore,
    ) {
        self.yearDataProvider = yearDataProvider
        self.evidenceController = evidenceController
        self.manualEntryController = manualEntryController
        self.manualDataImportController = manualDataImportController
        self.resetController = resetController
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
        let locationRepository = FileLocationSampleRepository(
            calendar: calendar,
            fileURL: baseURL.appending(path: "location-samples.json"),
        )
        let manualEntryRepository = FileManualLogEntryRepository(
            calendar: calendar,
            fileURL: baseURL.appending(path: "manual-entries.json"),
        )
        let evidenceRepository = FileEvidenceAttachmentRepository(
            fileURL: baseURL.appending(path: "evidence-index.json"),
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
        let manualDataImportController = ManualDataImportController(
            calendar: calendar,
            manualEntryRepository: manualEntryRepository,
            manualEntryController: manualEntryController,
            evidenceController: evidenceController,
        )
        let resetController = ResetController(
            locationRepository: locationRepository,
            manualEntryRepository: manualEntryRepository,
            evidenceAttachmentRepository: evidenceRepository,
            syncCheckpointStore: syncCheckpointStore,
            trackingStateStore: trackingStateStore,
            baseDirectoryURL: baseURL,
        )
        let yearExportController = YearExportController(
            calendar: calendar,
            yearDataProvider: yearDataProvider,
        )

        return Self(
            yearDataProvider: yearDataProvider,
            evidenceController: evidenceController,
            manualEntryController: manualEntryController,
            manualDataImportController: manualDataImportController,
            resetController: resetController,
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
