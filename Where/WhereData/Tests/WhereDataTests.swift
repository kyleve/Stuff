import Foundation
import Testing
import WhereCore
import WhereData

@Test
func yearProgressControllerBuildsSnapshot() async throws {
    let controller = YearProgressController()
    let years = await controller.availableYears()
    let year = try #require(years.last)

    let snapshot = await controller.snapshot(for: year)

    #expect(snapshot.year == year)
    #expect(snapshot.primarySummaries.count == 2)
    #expect(snapshot.secondarySummaries.contains { $0.jurisdiction == .unknown })
    #expect(snapshot.primarySummaries.first { $0.jurisdiction == .newYork }?.totalDays == 3)
    #expect(snapshot.secondarySummaries.first { $0.jurisdiction == .unknown }?.totalDays == 0)
    #expect(snapshot.trackingStatus == .healthy)
    #expect(!snapshot.recentDays.isEmpty)
}

@Test
func fileRepositoriesPersistAndFilterByYear() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    let locationRepository = FileLocationSampleRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "location-samples.json"),
    )
    let manualRepository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )

    let californiaSample = try LocationSample(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 9),
        jurisdiction: .california,
    )
    let newYorkSample = try LocationSample(
        timestamp: makeDate(year: 2025, month: 12, day: 31, hour: 21),
        jurisdiction: .newYork,
    )
    let entry = try ManualLogEntry(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
        jurisdiction: .newYork,
        note: "Train ticket attached",
        kind: .supplemental,
    )

    await locationRepository.upsert([californiaSample, newYorkSample])
    await manualRepository.save(entry)

    let years = await locationRepository.availableYears()
    let samples2026 = await locationRepository.samples(in: 2026)
    let manualYears = await manualRepository.availableYears()
    let entries2026 = await manualRepository.entries(in: 2026)

    #expect(years == [2025, 2026])
    #expect(samples2026 == [californiaSample])
    #expect(manualYears == [2026])
    #expect(entries2026 == [entry])
}

@Test
func evidenceControllerStoresMetadataAndBlobData() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    let attachmentRepository = FileEvidenceAttachmentRepository(
        fileURL: directory.appending(path: "evidence-index.json"),
    )
    let blobStore = FileEvidenceBlobStore(
        baseDirectoryURL: directory.appending(path: "evidence"),
    )
    let controller = EvidenceController(
        attachmentRepository: attachmentRepository,
        fileStore: blobStore,
    )
    let manualEntryID = UUID()
    let data = Data("ticket-pdf".utf8)

    let attachment = try await controller.importEvidence(
        manualEntryID: manualEntryID,
        originalFilename: "ticket.pdf",
        contentType: "application/pdf",
        data: data,
        createdAt: makeDate(year: 2026, month: 4, day: 5, hour: 12),
    )
    let attachments = await controller.attachments(for: manualEntryID)
    let loadedData = await controller.loadData(for: attachment)

    #expect(attachments == [attachment])
    #expect(attachment.storageKey == attachment.id.uuidString)
    #expect(loadedData == data)

    await controller.delete(attachment)

    let remainingAttachments = await controller.attachments(for: manualEntryID)
    let deletedData = await controller.loadData(for: attachment)

    #expect(remainingAttachments.isEmpty)
    #expect(deletedData == nil)
}

@Test
func yearProgressControllerMarksFailedSyncAsNeedsAttention() async throws {
    let year = 2026
    let sample = try LocationSample(
        timestamp: makeDate(year: year, month: 4, day: 5, hour: 9),
        jurisdiction: .california,
    )
    let provider = try SampleYearDataProvider(
        calendar: calendarUTC(),
        sampleData: [sample],
        manualEntries: [],
        evidenceAttachments: [],
        syncCheckpoint: .init(
            state: .failed,
            lastSuccessfulSyncAt: nil,
            lastAttemptAt: makeDate(year: year, month: 4, day: 5, hour: 10),
            failureReason: "CloudKit unavailable",
        ),
    )
    let controller = YearProgressController(
        calendar: calendarUTC(),
        yearDataProvider: provider,
    )

    let snapshot = await controller.snapshot(for: year)

    #expect(snapshot.trackingStatus == .needsAttention)
}

@Test
func manualEntryControllerSavesEntriesAndImportsEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    let repository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )
    let evidenceRepository = FileEvidenceAttachmentRepository(
        fileURL: directory.appending(path: "evidence-index.json"),
    )
    let evidenceController = EvidenceController(
        attachmentRepository: evidenceRepository,
        fileStore: FileEvidenceBlobStore(
            baseDirectoryURL: directory.appending(path: "evidence"),
        ),
    )
    let controller = ManualEntryController(
        repository: repository,
        evidenceController: evidenceController,
    )
    let draft = try ManualEntryDraft(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
        jurisdiction: .newYork,
        note: "  Boarding pass attached  ",
        kind: .correction,
    )
    let evidenceURL = directory.appending(path: "ticket.txt")

    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil,
    )
    try Data("ticket".utf8).write(to: evidenceURL)

    let saved = await controller.save(draft)
    let attachment = await controller.importEvidence(manualEntryID: saved.id, fileURL: evidenceURL)
    let records = await controller.records(in: 2026)

    #expect(saved.entry.note == "Boarding pass attached")
    #expect(attachment?.originalFilename == "ticket.txt")
    #expect(records.count == 1)
    #expect(records.first?.attachments.count == 1)
}

@Test
func manualEntryControllerDeletesEntriesAndAttachedEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    let repository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )
    let evidenceRepository = FileEvidenceAttachmentRepository(
        fileURL: directory.appending(path: "evidence-index.json"),
    )
    let evidenceController = EvidenceController(
        attachmentRepository: evidenceRepository,
        fileStore: FileEvidenceBlobStore(
            baseDirectoryURL: directory.appending(path: "evidence"),
        ),
    )
    let controller = ManualEntryController(
        repository: repository,
        evidenceController: evidenceController,
    )
    let draft = try ManualEntryDraft(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
        jurisdiction: .california,
        note: "Receipt attached",
        kind: .supplemental,
    )
    let evidenceURL = directory.appending(path: "receipt.txt")

    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil,
    )
    try Data("receipt".utf8).write(to: evidenceURL)

    let saved = await controller.save(draft)
    _ = await controller.importEvidence(manualEntryID: saved.id, fileURL: evidenceURL)

    await controller.deleteEntry(id: saved.id)

    let records = await controller.records(in: 2026)
    let attachments = await evidenceController.attachments(for: saved.id)

    #expect(records.isEmpty)
    #expect(attachments.isEmpty)
}

@Test
func manualEntryControllerCreatesPreviewFileURLForEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    let repository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )
    let evidenceRepository = FileEvidenceAttachmentRepository(
        fileURL: directory.appending(path: "evidence-index.json"),
    )
    let evidenceController = EvidenceController(
        attachmentRepository: evidenceRepository,
        fileStore: FileEvidenceBlobStore(
            baseDirectoryURL: directory.appending(path: "evidence"),
        ),
    )
    let controller = ManualEntryController(
        repository: repository,
        evidenceController: evidenceController,
    )
    let draft = try ManualEntryDraft(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
        jurisdiction: .california,
        note: "Passport stamp",
        kind: .supplemental,
    )
    let evidenceURL = directory.appending(path: "stamp.txt")

    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil,
    )
    try Data("stamp".utf8).write(to: evidenceURL)

    let saved = await controller.save(draft)
    let attachment = try #require(
        await controller.importEvidence(manualEntryID: saved.id, fileURL: evidenceURL),
    )
    let previewURL = await controller.evidenceFileURL(for: attachment)

    #expect(previewURL != nil)
    #expect(try Data(contentsOf: #require(previewURL)) == Data("stamp".utf8))
}

@Test
func fileManualLogEntryRepositoryBatchSaveMergesImportedEntries() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    let repository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )
    let original = try ManualLogEntry(
        id: UUID(),
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 9),
        jurisdiction: .california,
        note: "Original",
        kind: .supplemental,
    )
    let later = try ManualLogEntry(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 11),
        jurisdiction: .newYork,
        note: "Later",
        kind: .supplemental,
    )
    let updated = ManualLogEntry(
        id: original.id,
        timestamp: original.timestamp,
        jurisdiction: .newYork,
        note: "Updated",
        kind: .correction,
    )

    await repository.save([original, later])
    await repository.save([updated])

    let entries = await repository.entries(in: 2026)

    #expect(entries == [updated, later])
}

@Test
func manualDataImportControllerPreviewsBackfillAcrossYearBoundary() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil,
    )
    let evidenceURL = directory.appending(path: "ticket.txt")
    try Data("ticket".utf8).write(to: evidenceURL)

    let controller = makeManualDataImportController(directory: directory)
    let preview = try await controller.previewBackfill(
        ManualImportBackfillRequest(
            startDate: makeDate(year: 2025, month: 12, day: 31, hour: 9),
            endDate: makeDate(year: 2026, month: 1, day: 2, hour: 9),
            jurisdiction: .california,
            note: "Year boundary import",
            kind: .supplemental,
            evidenceFiles: [evidenceURL],
        ),
    )

    #expect(preview.isValid)
    #expect(preview.entryCount == 3)
    #expect(preview.evidenceAttachmentCount == 3)
    #expect(preview.sharedEvidenceAttachmentCount == 1)
    #expect(preview.yearSpan == 2025 ... 2026)
}

@Test
func manualDataImportControllerImportsPackageManifestWithEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(
        at: directory.appending(path: "evidence"),
        withIntermediateDirectories: true,
        attributes: nil,
    )
    let manifest = try ManualImportPackageManifest(
        entries: [
            .init(
                timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
                jurisdiction: .state("CA"),
                note: "Imported from manifest",
                kind: .supplemental,
                evidenceFilenames: ["ticket.txt"],
            ),
        ],
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: directory.appending(path: "manifest.json"))
    try Data("ticket-data".utf8).write(to: directory.appending(path: "evidence/ticket.txt"))

    let evidenceRepository = FileEvidenceAttachmentRepository(
        fileURL: directory.appending(path: "evidence-index.json"),
    )
    let evidenceController = EvidenceController(
        attachmentRepository: evidenceRepository,
        fileStore: FileEvidenceBlobStore(baseDirectoryURL: directory.appending(path: "evidence-store")),
    )
    let manualRepository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )
    let controller = ManualDataImportController(
        calendar: calendarUTC(),
        manualEntryRepository: manualRepository,
        manualEntryController: ManualEntryController(
            repository: manualRepository,
            evidenceController: evidenceController,
        ),
        evidenceController: evidenceController,
    )

    let preview = await controller.previewPackage(at: directory)
    let records = await controller.importPackage(at: directory)

    #expect(preview.isValid)
    #expect(preview.entryCount == 1)
    #expect(records.count == 1)
    #expect(records.first?.entry.jurisdiction == .california)
    #expect(records.first?.entry.note == "Imported from manifest")
    #expect(records.first?.attachments.count == 1)
    #expect(records.first?.attachments.first?.originalFilename == "ticket.txt")
}

@Test
func manualDataImportControllerFlagsMissingEvidenceInPackagePreview() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil,
    )
    let manifest = try ManualImportPackageManifest(
        entries: [
            .init(
                timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
                jurisdiction: .state("CA"),
                note: "Missing file",
                kind: .correction,
                evidenceFilenames: ["missing-ticket.txt"],
            ),
        ],
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: directory.appending(path: "manifest.json"))

    let controller = makeManualDataImportController(directory: directory)
    let preview = await controller.previewPackage(at: directory)

    #expect(!preview.isValid)
    #expect(preview.issues.contains { $0.message.contains("Missing evidence file") })
}

@Test
func manualDataImportControllerRollsBackEntriesWhenEvidencePersistenceFails() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil,
    )
    let evidenceURL = directory.appending(path: "ticket.txt")
    try Data("ticket".utf8).write(to: evidenceURL)

    let manualRepository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )
    let evidenceRepository = FileEvidenceAttachmentRepository(
        fileURL: directory.appending(path: "evidence-index.json"),
    )
    let evidenceController = EvidenceController(
        attachmentRepository: evidenceRepository,
        fileStore: FailingEvidenceFileStore(),
    )
    let controller = ManualDataImportController(
        calendar: calendarUTC(),
        manualEntryRepository: manualRepository,
        manualEntryController: ManualEntryController(
            repository: manualRepository,
            evidenceController: evidenceController,
        ),
        evidenceController: evidenceController,
    )
    let entry = try ManualImportEntryDraft(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
        jurisdiction: .newYork,
        note: "Should roll back",
        kind: .supplemental,
        evidenceFiles: [evidenceURL],
    )

    let imported = await controller.importEntries([entry])

    #expect(imported.isEmpty)
    #expect(await manualRepository.entries(in: 2026).isEmpty)
    #expect(await evidenceRepository.attachments(for: entry.id).isEmpty)
}

@Test
func yearExportControllerBuildsPlainTextAndPDFBundle() async throws {
    let year = 2026
    let generatedAt = try makeDate(year: year, month: 4, day: 6, hour: 18)
    let sample = try LocationSample(
        timestamp: makeDate(year: year, month: 4, day: 5, hour: 9),
        jurisdiction: .california,
    )
    let manualEntry = try ManualLogEntry(
        timestamp: makeDate(year: year, month: 4, day: 5, hour: 12),
        jurisdiction: .newYork,
        note: "Attached ticket",
        kind: .supplemental,
    )
    let attachment = try EvidenceAttachment(
        manualEntryID: manualEntry.id,
        originalFilename: "train-ticket.pdf",
        contentType: "application/pdf",
        byteCount: 42000,
        createdAt: makeDate(year: year, month: 4, day: 5, hour: 12),
    )
    let provider = SampleYearDataProvider(
        calendar: calendarUTC(),
        sampleData: [sample],
        manualEntries: [manualEntry],
        evidenceAttachments: [attachment],
        trackingState: TrackingState(
            authorizationStatus: .authorizedAlways,
            lastWakeEventAt: generatedAt,
            lastRecordedSampleAt: generatedAt,
            lastWakeReason: .manualRefresh,
            isMonitoringActive: true,
        ),
    )
    let controller = YearExportController(
        calendar: calendarUTC(),
        yearDataProvider: provider,
        generatedAt: { generatedAt },
    )

    let bundle = await controller.exportBundle(for: year)

    #expect(bundle.plaintext.contains("Where Tax Report"))
    #expect(bundle.plaintext.contains("Manual Entries"))
    #expect(bundle.plaintext.contains("train-ticket.pdf"))
    #expect(bundle.pdfData.contains(Data("Where Tax Report".utf8)))
    #expect(bundle.pdfData.contains(Data("Daily Ledger".utf8)))
    #expect(bundle.pdfData.contains(Data("Manual Entries".utf8)))
    #expect(bundle.plaintextFilename == "where-2026-report.txt")
    #expect(bundle.pdfFilename == "where-2026-report.pdf")
    #expect(String(decoding: bundle.pdfData.prefix(8), as: UTF8.self).hasPrefix("%PDF-1.4"))
}

@Test
func resetControllerClearsPersistedWhereData() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
    let locationRepository = FileLocationSampleRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "location-samples.json"),
    )
    let manualRepository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )
    let evidenceRepository = FileEvidenceAttachmentRepository(
        fileURL: directory.appending(path: "evidence-index.json"),
    )
    let syncCheckpointStore = FileSyncCheckpointStore(
        fileURL: directory.appending(path: "sync-checkpoint.json"),
    )
    let trackingStateStore = FileTrackingStateStore(
        fileURL: directory.appending(path: "tracking-state.json"),
    )
    let evidenceController = EvidenceController(
        attachmentRepository: evidenceRepository,
        fileStore: FileEvidenceBlobStore(
            baseDirectoryURL: directory.appending(path: "evidence"),
        ),
    )
    let resetController = ResetController(
        locationRepository: locationRepository,
        manualEntryRepository: manualRepository,
        evidenceAttachmentRepository: evidenceRepository,
        syncCheckpointStore: syncCheckpointStore,
        trackingStateStore: trackingStateStore,
        baseDirectoryURL: directory,
    )

    let sample = try LocationSample(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 9),
        jurisdiction: .california,
    )
    let entry = try ManualLogEntry(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
        jurisdiction: .newYork,
        note: "Reset me",
        kind: .correction,
    )
    await locationRepository.upsert([sample])
    await manualRepository.save(entry)
    _ = await evidenceController.importEvidence(
        manualEntryID: entry.id,
        originalFilename: "ticket.txt",
        contentType: "text/plain",
        data: Data("ticket".utf8),
    )
    await syncCheckpointStore.save(
        SyncCheckpoint(
            state: .failed,
            failureReason: "Network",
        ),
    )
    try await trackingStateStore.save(
        TrackingState(
            authorizationStatus: .authorizedAlways,
            lastRecordedSampleAt: makeDate(year: 2026, month: 4, day: 5, hour: 9),
            isMonitoringActive: true,
        ),
    )

    await resetController.resetAllData()

    #expect(await locationRepository.samples(in: 2026).isEmpty)
    #expect(await manualRepository.entries(in: 2026).isEmpty)
    #expect(await evidenceRepository.attachments(for: entry.id).isEmpty)
    #expect(await syncCheckpointStore.checkpoint() == .init(state: .idle))
    #expect(await trackingStateStore.load() == TrackingState(authorizationStatus: .notDetermined))
}

@Test
func backgroundTrackingControllerStartsMonitoringAfterAuthorization() async {
    let locationRepository = InMemoryLocationSampleRepository()
    let authorizationProvider = StubLocationAuthorizationProvider(status: .authorizedAlways)
    let wakeSource = StubLocationWakeSource()
    let notificationScheduler = StubTrackingNotificationScheduler()
    let trackingStateStore = InMemoryTrackingStateStore(
        state: TrackingState(authorizationStatus: .notDetermined),
    )
    let controller = BackgroundTrackingController(
        calendar: calendarUTC(),
        locationRepository: locationRepository,
        authorizationProvider: authorizationProvider,
        wakeSource: wakeSource,
        jurisdictionResolver: StubJurisdictionResolver(jurisdiction: .california),
        notificationScheduler: notificationScheduler,
        trackingStateController: TrackingStateController(store: trackingStateStore),
        now: { try! makeDate(year: 2026, month: 4, day: 6, hour: 9) },
    )

    await controller.prepareForLaunch()
    let state = await controller.trackingState()

    #expect(await wakeSource.startedMonitoringCount == 1)
    #expect(await wakeSource.stoppedMonitoringCount == 0)
    #expect(state.authorizationStatus == .authorizedAlways)
    #expect(state.isMonitoringActive)
}

@Test
func backgroundTrackingControllerStoresWakeEventsAsLocationSamples() async throws {
    let locationRepository = InMemoryLocationSampleRepository()
    let controller = BackgroundTrackingController(
        calendar: calendarUTC(),
        locationRepository: locationRepository,
        authorizationProvider: StubLocationAuthorizationProvider(status: .authorizedAlways),
        wakeSource: StubLocationWakeSource(),
        jurisdictionResolver: StubJurisdictionResolver(jurisdiction: .newYork),
        notificationScheduler: StubTrackingNotificationScheduler(),
        trackingStateController: TrackingStateController(
            store: InMemoryTrackingStateStore(
                state: TrackingState(
                    authorizationStatus: .authorizedAlways,
                    isMonitoringActive: true,
                ),
            ),
        ),
        now: { try! makeDate(year: 2026, month: 4, day: 6, hour: 9) },
    )
    let wakeDate = try makeDate(year: 2026, month: 4, day: 5, hour: 11)

    await controller.handleWakeEvent(
        TrackingWakeEvent(
            timestamp: wakeDate,
            reason: .visit,
            latitude: 40.7128,
            longitude: -74.0060,
        ),
    )
    let samples = await locationRepository.samples(in: 2026)
    let state = await controller.trackingState()

    #expect(samples.count == 1)
    #expect(samples.first?.jurisdiction == .newYork)
    #expect(state.lastWakeEventAt == wakeDate)
    #expect(state.lastRecordedSampleAt == wakeDate)
    #expect(state.lastWakeReason == .visit)
}

@Test
func backgroundTrackingControllerSchedulesGapNotificationsForStaleTracking() async throws {
    let notificationScheduler = StubTrackingNotificationScheduler()
    let staleDate = try makeDate(year: 2026, month: 4, day: 3, hour: 9)
    let nowDate = try makeDate(year: 2026, month: 4, day: 6, hour: 9)
    let controller = BackgroundTrackingController(
        calendar: calendarUTC(),
        locationRepository: InMemoryLocationSampleRepository(),
        authorizationProvider: StubLocationAuthorizationProvider(status: .authorizedAlways),
        wakeSource: StubLocationWakeSource(),
        jurisdictionResolver: StubJurisdictionResolver(jurisdiction: .california),
        notificationScheduler: notificationScheduler,
        trackingStateController: TrackingStateController(
            store: InMemoryTrackingStateStore(
                state: TrackingState(
                    authorizationStatus: .authorizedAlways,
                    lastRecordedSampleAt: staleDate,
                    isMonitoringActive: true,
                ),
            ),
        ),
        now: { nowDate },
    )

    await controller.refreshMonitoring()
    let state = await controller.trackingState()
    let scheduledRequests = await notificationScheduler.scheduledRequests

    #expect(await notificationScheduler.cancelledIDs.isEmpty)
    #expect(scheduledRequests.count == 3)
    #expect(state.pendingGapNotificationDates.count == 3)
}

@Test
func backgroundTrackingControllerStopsMonitoringWhenAuthorizationIsLost() async throws {
    let wakeSource = StubLocationWakeSource()
    let notificationScheduler = StubTrackingNotificationScheduler()
    let controller = try BackgroundTrackingController(
        calendar: calendarUTC(),
        locationRepository: InMemoryLocationSampleRepository(),
        authorizationProvider: StubLocationAuthorizationProvider(status: .denied),
        wakeSource: wakeSource,
        jurisdictionResolver: StubJurisdictionResolver(jurisdiction: .unknown),
        notificationScheduler: notificationScheduler,
        trackingStateController: TrackingStateController(
            store: InMemoryTrackingStateStore(
                state: TrackingState(
                    authorizationStatus: .authorizedAlways,
                    pendingGapNotificationDates: [makeDate(year: 2026, month: 4, day: 6, hour: 20)],
                    isMonitoringActive: true,
                ),
            ),
        ),
        now: { try! makeDate(year: 2026, month: 4, day: 6, hour: 9) },
    )

    await controller.handleAuthorizationStatusChange(.denied)
    let state = await controller.trackingState()

    #expect(await wakeSource.stoppedMonitoringCount == 1)
    #expect(await notificationScheduler.cancelledIDs.count == 1)
    #expect(state.authorizationStatus == .denied)
    #expect(!state.isMonitoringActive)
    #expect(state.pendingGapNotificationDates.isEmpty)
}

private func calendarUTC() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}

private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
) throws -> Date {
    let components = DateComponents(
        calendar: calendarUTC(),
        year: year,
        month: month,
        day: day,
        hour: hour,
    )

    return try #require(components.date)
}

private func makeManualDataImportController(directory: URL) -> ManualDataImportController {
    let manualRepository = FileManualLogEntryRepository(
        calendar: calendarUTC(),
        fileURL: directory.appending(path: "manual-entries.json"),
    )
    let evidenceController = EvidenceController(
        attachmentRepository: FileEvidenceAttachmentRepository(
            fileURL: directory.appending(path: "evidence-index.json"),
        ),
        fileStore: FileEvidenceBlobStore(
            baseDirectoryURL: directory.appending(path: "evidence-store"),
        ),
    )

    return ManualDataImportController(
        calendar: calendarUTC(),
        manualEntryRepository: manualRepository,
        manualEntryController: ManualEntryController(
            repository: manualRepository,
            evidenceController: evidenceController,
        ),
        evidenceController: evidenceController,
    )
}

private actor InMemoryLocationSampleRepository: LocationSampleRepository {
    private var samples: [LocationSample] = []

    func availableYears() async -> [Int] {
        let years = Set(samples.map { calendarUTC().component(.year, from: $0.timestamp) })
        return years.sorted()
    }

    func samples(in year: Int) async -> [LocationSample] {
        samples
            .filter { calendarUTC().component(.year, from: $0.timestamp) == year }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func upsert(_ samples: [LocationSample]) async {
        var merged = Dictionary(uniqueKeysWithValues: self.samples.map { ($0.id, $0) })
        for sample in samples {
            merged[sample.id] = sample
        }
        self.samples = merged.values.sorted { $0.timestamp < $1.timestamp }
    }

    func removeAll() async {
        samples = []
    }
}

private actor InMemoryTrackingStateStore: TrackingStateStore {
    private var state: TrackingState

    init(state: TrackingState) {
        self.state = state
    }

    func load() async -> TrackingState {
        state
    }

    func save(_ state: TrackingState) async {
        self.state = state
    }

    func reset() async {
        state = TrackingState(authorizationStatus: .notDetermined)
    }
}

private actor FailingEvidenceFileStore: EvidenceFileStore {
    func save(_: Data, for _: EvidenceAttachment) async {}

    func load(for _: EvidenceAttachment) async -> Data? {
        nil
    }

    func delete(for _: EvidenceAttachment) async {}
}

private actor StubLocationWakeSource: LocationWakeSource {
    private(set) var startedMonitoringCount = 0
    private(set) var refreshedMonitoringCount = 0
    private(set) var stoppedMonitoringCount = 0

    func startMonitoring(configuration _: TrackingMonitoringConfiguration) async {
        startedMonitoringCount += 1
    }

    func refreshRegionMonitoring(configuration _: TrackingMonitoringConfiguration) async {
        refreshedMonitoringCount += 1
    }

    func stopMonitoring() async {
        stoppedMonitoringCount += 1
    }
}

private actor StubLocationAuthorizationProvider: LocationAuthorizationProviding {
    private var status: TrackingAuthorizationStatus

    init(status: TrackingAuthorizationStatus) {
        self.status = status
    }

    func currentAuthorizationStatus() async -> TrackingAuthorizationStatus {
        status
    }

    func requestAlwaysAuthorization() async {
        status = .authorizedAlways
    }
}

private struct StubJurisdictionResolver: JurisdictionResolving {
    let jurisdiction: TaxJurisdiction

    func jurisdiction(for _: TrackingWakeEvent) async -> TaxJurisdiction {
        jurisdiction
    }
}

private actor StubTrackingNotificationScheduler: TrackingNotificationScheduling {
    private(set) var scheduledRequests: [TrackingNotificationRequest] = []
    private(set) var cancelledIDs: [String] = []

    func schedule(_ request: TrackingNotificationRequest) async {
        scheduledRequests.append(request)
    }

    func cancel(ids: [String]) async {
        cancelledIDs.append(contentsOf: ids)
    }
}
