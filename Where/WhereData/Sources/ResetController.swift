import Foundation
import WhereCore

public actor ResetController: WhereDataResetting {
    private let locationRepository: any LocationSampleRepository
    private let manualEntryRepository: any ManualLogEntryRepository
    private let evidenceAttachmentRepository: any EvidenceAttachmentRepository
    private let syncCheckpointStore: any SyncCheckpointStore
    private let trackingStateStore: any TrackingStateStore
    private let fileManager: FileManager
    private let baseDirectoryURL: URL

    public init(
        locationRepository: any LocationSampleRepository,
        manualEntryRepository: any ManualLogEntryRepository,
        evidenceAttachmentRepository: any EvidenceAttachmentRepository,
        syncCheckpointStore: any SyncCheckpointStore,
        trackingStateStore: any TrackingStateStore,
        baseDirectoryURL: URL,
        fileManager: FileManager = .default,
    ) {
        self.locationRepository = locationRepository
        self.manualEntryRepository = manualEntryRepository
        self.evidenceAttachmentRepository = evidenceAttachmentRepository
        self.syncCheckpointStore = syncCheckpointStore
        self.trackingStateStore = trackingStateStore
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
    }

    public func resetAllData() async {
        await locationRepository.removeAll()
        await manualEntryRepository.removeAll()
        await evidenceAttachmentRepository.removeAll()
        await syncCheckpointStore.reset()
        await trackingStateStore.reset()

        let evidenceDirectory = baseDirectoryURL.appending(path: "evidence")
        try? fileManager.removeItem(at: evidenceDirectory)
    }
}
