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
                exporter: StubYearExporter(),
                yearDataProvider: StubYearDataProvider(),
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
        exporter: StubYearExporter(generatedAt: generatedAt),
        yearDataProvider: StubYearDataProvider(),
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
        exporter: StubYearExporter(),
        yearDataProvider: StubYearDataProvider(),
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
        exporter: StubYearExporter(generatedAt: generatedAt),
        yearDataProvider: StubYearDataProvider(bundle: bundle),
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

    func availableYears() async -> [Int] {
        [bundle.year]
    }

    func bundle(for year: Int) async -> YearDataBundle {
        if year == bundle.year {
            return bundle
        }

        return YearDataBundle(
            year: year,
            locationSamples: [],
            manualEntries: [],
            evidenceAttachments: [],
            syncCheckpoint: .init(state: .idle),
        )
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
