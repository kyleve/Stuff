import Foundation
import SwiftUI
import Testing
import WhereCore
import WhereTesting
import WhereUI

@Test
@MainActor
func rootViewBuilds() throws {
    let vc = UIHostingController(
        rootView: RootView(
            viewModel: RootViewModel(provider: StubYearProgressProvider()),
            manualEntryViewModel: ManualEntryViewModel(
                manager: StubManualEntryManager(),
                importer: StubManualImporter(),
                exporter: StubYearExporter(),
                yearDataProvider: StubYearDataProvider(),
                resetter: StubDataResetter(),
            ),
        ),
    )

    try show(vc) { hosted in
        #expect(hosted.view != nil)
    }
}

@Test
@MainActor
func manualEntryViewModelStagesReportShareFiles() async throws {
    let generatedAt = try makeDate(year: 2026, month: 4, day: 6, hour: 18)
    let viewModel = ManualEntryViewModel(
        manager: StubManualEntryManager(),
        importer: StubManualImporter(),
        exporter: StubYearExporter(generatedAt: generatedAt),
        yearDataProvider: StubYearDataProvider(),
        resetter: StubDataResetter(),
        calendar: calendarUTC(),
    )

    await viewModel.preparePlainTextShare(for: 2026)
    let textURL = try #require(viewModel.shareURL)
    let textActivity = try #require(viewModel.reportActivity(for: 2026, format: .plainText))

    #expect(textURL.lastPathComponent == "where-2026-report.txt")
    #expect(try String(contentsOf: textURL, encoding: .utf8) == "Where Tax Report")
    #expect(textActivity.generatedAt == generatedAt)
    #expect(textActivity.triggerDescription == "prepared for sharing on")

    viewModel.clearShare()

    await viewModel.preparePDFShare(for: 2026)
    let pdfURL = try #require(viewModel.shareURL)
    let pdfPrefix = try String(decoding: Data(contentsOf: pdfURL).prefix(8), as: UTF8.self)
    let pdfActivity = try #require(viewModel.reportActivity(for: 2026, format: .pdf))

    #expect(pdfURL.lastPathComponent == "where-2026-report.pdf")
    #expect(pdfPrefix.hasPrefix("%PDF-1.4"))
    #expect(pdfActivity.generatedAt == generatedAt)
    #expect(pdfActivity.triggerDescription == "prepared for sharing on")
}

@Test
@MainActor
func manualEntryViewModelCachesInlineEvidenceURLForPreview() async throws {
    let tempURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
    try Data("preview".utf8).write(to: tempURL)

    let manager = PreviewManualEntryManager(evidenceURL: tempURL)
    let viewModel = ManualEntryViewModel(
        manager: manager,
        importer: StubManualImporter(),
        exporter: StubYearExporter(),
        yearDataProvider: StubYearDataProvider(),
        resetter: StubDataResetter(),
    )
    let attachment = EvidenceAttachment(
        manualEntryID: UUID(),
        originalFilename: "boarding-pass.png",
        contentType: "image/png",
        byteCount: 7,
    )

    await viewModel.loadInlineEvidenceIfNeeded(for: attachment)
    await viewModel.prepareEvidencePreview(for: attachment)

    #expect(viewModel.inlineEvidenceURL(for: attachment) == tempURL)
    #expect(viewModel.previewURL == tempURL)
    #expect(await manager.evidenceURLRequestCount == 1)
}

@Test
@MainActor
func manualEntryViewModelBuildsGroupedDaySectionsAndHighlightsOutcomeChanges() async throws {
    let generatedAt = try makeDate(year: 2026, month: 4, day: 6, hour: 18)
    let trackedSample = try LocationSample(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 8),
        jurisdiction: .california,
    )
    let unchangedEntry = try ManualLogEntry(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 9),
        jurisdiction: .california,
        note: "Existing tracked jurisdiction",
        kind: .supplemental,
    )
    let changedEntry = try ManualLogEntry(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 12),
        jurisdiction: .newYork,
        note: "Flight evidence adds New York",
        kind: .supplemental,
    )
    let bundle = YearDataBundle(
        year: 2026,
        locationSamples: [trackedSample],
        manualEntries: [unchangedEntry, changedEntry],
        evidenceAttachments: [],
        syncCheckpoint: .init(state: .idle),
    )
    let viewModel = ManualEntryViewModel(
        manager: StubManualEntryManager(
            records: [
                ManualEntryRecord(entry: changedEntry, attachments: []),
                ManualEntryRecord(entry: unchangedEntry, attachments: []),
            ],
        ),
        importer: StubManualImporter(),
        exporter: StubYearExporter(generatedAt: generatedAt),
        yearDataProvider: StubYearDataProvider(bundle: bundle),
        resetter: StubDataResetter(),
        calendar: calendarUTC(),
    )

    await viewModel.load(for: 2026)
    await viewModel.preparePDFExport(for: 2026)

    let section = try #require(viewModel.daySections.first)
    let exportActivity = try #require(viewModel.reportActivity(for: 2026, format: .pdf))

    #expect(viewModel.daySections.count == 1)
    #expect(section.changesTrackedOutcome)
    #expect(section.trackedJurisdictions == [.california])
    #expect(section.finalJurisdictions == [.california, .newYork])
    #expect(section.entries.count == 2)
    #expect(section.entries.first { $0.record.id == changedEntry.id }?.changesDayOutcome == true)
    #expect(section.entries.first { $0.record.id == unchangedEntry.id }?.changesDayOutcome == false)
    #expect(exportActivity.generatedAt == generatedAt)
    #expect(exportActivity.triggerDescription == "prepared for save on")
}

@Test
@MainActor
func manualEntryViewModelResetsStoredDataAndClearsUIState() async throws {
    let trackedSample = try LocationSample(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 8),
        jurisdiction: .california,
    )
    let entry = try ManualLogEntry(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 12),
        jurisdiction: .newYork,
        note: "Flight correction",
        kind: .correction,
    )
    let record = ManualEntryRecord(entry: entry, attachments: [])
    let manager = MutableManualEntryManager(records: [record])
    let provider = MutableYearDataProvider(
        bundle: YearDataBundle(
            year: 2026,
            locationSamples: [trackedSample],
            manualEntries: [entry],
            evidenceAttachments: [],
            syncCheckpoint: .init(state: .idle),
        ),
    )
    let resetter = StubDataResetter(
        manager: manager,
        provider: provider,
    )
    let viewModel = ManualEntryViewModel(
        manager: manager,
        importer: StubManualImporter(),
        exporter: StubYearExporter(),
        yearDataProvider: provider,
        resetter: resetter,
        calendar: calendarUTC(),
    )

    await viewModel.load(for: 2026)
    viewModel.requestResetConfirmation()
    await viewModel.resetAllData(for: 2026)

    #expect(viewModel.records.isEmpty)
    #expect(viewModel.daySections.isEmpty)
    #expect(!viewModel.isShowingResetConfirmation)
    #expect(await resetter.resetCount == 1)
}

@Test
@MainActor
func manualEntryViewModelPreviewsBackfillImports() async throws {
    let evidenceURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
    try Data("ticket".utf8).write(to: evidenceURL)
    let importer = StubManualImporter()
    let viewModel = ManualEntryViewModel(
        manager: StubManualEntryManager(),
        importer: importer,
        exporter: StubYearExporter(),
        yearDataProvider: StubYearDataProvider(),
        resetter: StubDataResetter(),
        calendar: calendarUTC(),
    )

    try await viewModel.previewBackfill(
        ManualImportBackfillRequest(
            startDate: makeDate(year: 2026, month: 4, day: 5, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 6, hour: 8),
            jurisdiction: .california,
            note: "Backfill request",
            kind: .supplemental,
            evidenceFiles: [evidenceURL],
        ),
    )

    let preview = try #require(viewModel.activeImportPreview)
    #expect(viewModel.isShowingImportPreview)
    #expect(viewModel.importSourceDescription == "Backfill")
    #expect(preview.entryCount == 2)
    #expect(preview.evidenceAttachmentCount == 2)
}

@Test
@MainActor
func manualEntryViewModelPreviewsPackageImportsAndConfirmsImport() async throws {
    let importedEntry = try ManualLogEntry(
        timestamp: makeDate(year: 2026, month: 4, day: 5, hour: 10),
        jurisdiction: .newYork,
        note: "Imported package row",
        kind: .supplemental,
    )
    let importedRecord = ManualEntryRecord(
        entry: importedEntry,
        attachments: [
            EvidenceAttachment(
                manualEntryID: importedEntry.id,
                originalFilename: "ticket.txt",
                contentType: "text/plain",
                byteCount: 6,
            ),
        ],
    )
    let manager = MutableManualEntryManager(records: [])
    let provider = MutableYearDataProvider(
        bundle: YearDataBundle(
            year: 2026,
            locationSamples: [],
            manualEntries: [],
            evidenceAttachments: [],
            syncCheckpoint: .init(state: .idle),
        ),
    )
    let importer = StubManualImporter(importPackageResult: [importedRecord])
    let viewModel = ManualEntryViewModel(
        manager: manager,
        importer: importer,
        exporter: StubYearExporter(),
        yearDataProvider: provider,
        resetter: StubDataResetter(),
        calendar: calendarUTC(),
    )
    let packageURL = FileManager.default.temporaryDirectory.appending(path: "where-import-package")

    await viewModel.previewPackage(at: packageURL)
    let preview = try #require(viewModel.activeImportPreview)
    #expect(viewModel.importSourceDescription == "where-import-package")
    #expect(preview.entryCount == 1)
    #expect(preview.hasWarnings)

    await manager.replaceRecords([importedRecord])
    await provider.replaceBundle(
        YearDataBundle(
            year: 2026,
            locationSamples: [],
            manualEntries: [importedEntry],
            evidenceAttachments: importedRecord.attachments,
            syncCheckpoint: .init(state: .idle),
        ),
    )

    await viewModel.confirmImport(for: 2026)

    #expect(!viewModel.isShowingImportPreview)
    #expect(viewModel.records.count == 1)
    #expect(viewModel.daySections.count == 1)
    #expect(await importer.importedPackageURLs == [packageURL])
}

private struct StubYearProgressProvider: YearProgressProviding {
    func availableYears() async -> [Int] {
        [2026]
    }

    func snapshot(for year: Int) async -> YearProgressSnapshot {
        YearProgressSnapshot(
            year: year,
            primarySummaries: [
                .init(jurisdiction: .california, totalDays: 10),
                .init(jurisdiction: .newYork, totalDays: 8),
            ],
            secondarySummaries: [
                .init(jurisdiction: .unknown, totalDays: 1),
            ],
            trackingStatus: .needsReview,
            recentDays: [
                .init(
                    dateLabel: "Apr 6",
                    jurisdictions: [.california, .newYork],
                    note: "Multiple jurisdictions logged",
                ),
            ],
        )
    }
}

private struct StubManualEntryManager: ManualEntryManaging {
    var records: [ManualEntryRecord] = []

    func records(in _: Int) async -> [ManualEntryRecord] {
        records
    }

    func save(_ draft: ManualEntryDraft) async -> ManualEntryRecord {
        ManualEntryRecord(
            entry: ManualLogEntry(
                id: draft.id ?? UUID(),
                timestamp: draft.timestamp,
                jurisdiction: draft.jurisdiction,
                note: draft.trimmedNote,
                kind: draft.kind,
            ),
            attachments: [],
        )
    }

    func deleteEntry(id _: UUID) async {}

    func importEvidence(manualEntryID _: UUID, fileURL _: URL) async -> EvidenceAttachment? {
        nil
    }

    func evidenceFileURL(for _: EvidenceAttachment) async -> URL? {
        nil
    }

    func deleteEvidence(_: EvidenceAttachment) async {}
}

private actor StubManualImporter: ManualDataImporting {
    var backfillPreview = ManualImportPreview(
        yearSpan: 2026 ... 2026,
        entryCount: 2,
        evidenceAttachmentCount: 2,
        sharedEvidenceAttachmentCount: 1,
        entries: [
            ManualImportEntryDraft(
                timestamp: Date(),
                jurisdiction: .california,
                note: "Backfill preview",
                kind: .supplemental,
                evidenceFiles: [],
            ),
            ManualImportEntryDraft(
                timestamp: Date().addingTimeInterval(86400),
                jurisdiction: .california,
                note: "Backfill preview",
                kind: .supplemental,
                evidenceFiles: [],
            ),
        ],
    )
    var packagePreview = ManualImportPreview(
        yearSpan: 2025 ... 2026,
        entryCount: 1,
        evidenceAttachmentCount: 1,
        sharedEvidenceAttachmentCount: 0,
        entries: [
            ManualImportEntryDraft(
                timestamp: Date(),
                jurisdiction: .newYork,
                note: "Package preview",
                kind: .supplemental,
                evidenceFiles: [],
            ),
        ],
        issues: [
            .init(severity: .warning, message: "This package spans multiple years (2025-2026)."),
        ],
    )
    var importEntriesResult: [ManualEntryRecord] = []
    var importPackageResult: [ManualEntryRecord] = []
    private(set) var importedPackageURLs: [URL] = []

    init(
        importEntriesResult: [ManualEntryRecord] = [],
        importPackageResult: [ManualEntryRecord] = [],
    ) {
        self.importEntriesResult = importEntriesResult
        self.importPackageResult = importPackageResult
    }

    func previewBackfill(_ request: ManualImportBackfillRequest) async -> ManualImportPreview {
        ManualImportPreview(
            yearSpan: 2026 ... 2026,
            entryCount: 2,
            evidenceAttachmentCount: request.evidenceFiles.count * 2,
            sharedEvidenceAttachmentCount: request.evidenceFiles.count,
            entries: backfillPreview.entries,
        )
    }

    func previewPackage(at _: URL) async -> ManualImportPreview {
        packagePreview
    }

    func importEntries(_: [ManualImportEntryDraft]) async -> [ManualEntryRecord] {
        importEntriesResult
    }

    func importPackage(at directoryURL: URL) async -> [ManualEntryRecord] {
        importedPackageURLs.append(directoryURL)
        return importPackageResult
    }
}

private struct StubYearExporter: YearExporting {
    let generatedAt: Date

    init(generatedAt: Date = Date()) {
        self.generatedAt = generatedAt
    }

    func exportBundle(for year: Int) async -> YearExportBundle {
        YearExportBundle(
            year: year,
            generatedAt: generatedAt,
            plaintext: "Where Tax Report",
            pdfData: Data("%PDF-1.4".utf8),
        )
    }
}

private struct StubYearDataProvider: YearDataProviding {
    var bundle: YearDataBundle = .init(
        year: 2026,
        locationSamples: [],
        manualEntries: [],
        evidenceAttachments: [],
        syncCheckpoint: .init(state: .idle),
    )
    var fallbackBundle: YearDataBundle?

    func availableYears() async -> [Int] {
        [bundle.year]
    }

    func bundle(for year: Int) async -> YearDataBundle {
        if year == bundle.year {
            return bundle
        }

        return fallbackBundle ?? YearDataBundle(
            year: year,
            locationSamples: [],
            manualEntries: [],
            evidenceAttachments: [],
            syncCheckpoint: .init(state: .idle),
        )
    }
}

private actor StubDataResetter: WhereDataResetting {
    private let manager: MutableManualEntryManager?
    private let provider: MutableYearDataProvider?
    private(set) var resetCount = 0

    init(
        manager: MutableManualEntryManager? = nil,
        provider: MutableYearDataProvider? = nil,
    ) {
        self.manager = manager
        self.provider = provider
    }

    func resetAllData() async {
        resetCount += 1
        await manager?.replaceRecords([])
        await provider?.replaceBundle(
            YearDataBundle(
                year: 2026,
                locationSamples: [],
                manualEntries: [],
                evidenceAttachments: [],
                syncCheckpoint: .init(state: .idle),
            ),
        )
    }
}

private actor MutableManualEntryManager: ManualEntryManaging {
    private var storedRecords: [ManualEntryRecord]

    init(records: [ManualEntryRecord]) {
        storedRecords = records
    }

    func records(in _: Int) async -> [ManualEntryRecord] {
        storedRecords
    }

    func save(_ draft: ManualEntryDraft) async -> ManualEntryRecord {
        let record = ManualEntryRecord(
            entry: ManualLogEntry(
                id: draft.id ?? UUID(),
                timestamp: draft.timestamp,
                jurisdiction: draft.jurisdiction,
                note: draft.trimmedNote,
                kind: draft.kind,
            ),
            attachments: [],
        )
        storedRecords = [record]
        return record
    }

    func deleteEntry(id: UUID) async {
        storedRecords.removeAll { $0.id == id }
    }

    func importEvidence(manualEntryID _: UUID, fileURL _: URL) async -> EvidenceAttachment? {
        nil
    }

    func evidenceFileURL(for _: EvidenceAttachment) async -> URL? {
        nil
    }

    func deleteEvidence(_: EvidenceAttachment) async {}

    func replaceRecords(_ records: [ManualEntryRecord]) async {
        storedRecords = records
    }
}

private actor MutableYearDataProvider: YearDataProviding {
    private var storedBundle: YearDataBundle

    init(bundle: YearDataBundle) {
        storedBundle = bundle
    }

    func availableYears() async -> [Int] {
        [storedBundle.year]
    }

    func bundle(for year: Int) async -> YearDataBundle {
        if year == storedBundle.year {
            return storedBundle
        }

        return YearDataBundle(
            year: year,
            locationSamples: [],
            manualEntries: [],
            evidenceAttachments: [],
            syncCheckpoint: .init(state: .idle),
        )
    }

    func replaceBundle(_ bundle: YearDataBundle) async {
        storedBundle = bundle
    }
}

private actor PreviewManualEntryManager: ManualEntryManaging {
    private let evidenceURL: URL
    private(set) var evidenceURLRequestCount = 0

    init(evidenceURL: URL) {
        self.evidenceURL = evidenceURL
    }

    func records(in _: Int) async -> [ManualEntryRecord] {
        []
    }

    func save(_ draft: ManualEntryDraft) async -> ManualEntryRecord {
        ManualEntryRecord(
            entry: ManualLogEntry(
                id: draft.id ?? UUID(),
                timestamp: draft.timestamp,
                jurisdiction: draft.jurisdiction,
                note: draft.trimmedNote,
                kind: draft.kind,
            ),
            attachments: [],
        )
    }

    func deleteEntry(id _: UUID) async {}

    func importEvidence(manualEntryID _: UUID, fileURL _: URL) async -> EvidenceAttachment? {
        nil
    }

    func evidenceFileURL(for _: EvidenceAttachment) async -> URL? {
        evidenceURLRequestCount += 1
        return evidenceURL
    }

    func deleteEvidence(_: EvidenceAttachment) async {}
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
