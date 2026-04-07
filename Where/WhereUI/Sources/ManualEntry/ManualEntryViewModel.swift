import Foundation
import Observation
import WhereCore

@MainActor
@Observable
public final class ManualEntryViewModel {
    public private(set) var records: [ManualEntryRecord] = []
    public private(set) var daySections: [ManualEntryDaySection] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var plainTextExportDocument: PlainTextExportDocument?
    public private(set) var plainTextFilename = "where-export"
    public private(set) var pdfExportDocument: PDFExportDocument?
    public private(set) var pdfFilename = "where-export"
    public private(set) var previewURL: URL?
    public private(set) var shareURL: URL?

    private let manager: any ManualEntryManaging
    private let exporter: any YearExporting
    private let yearDataProvider: any YearDataProviding
    private let ledgerBuilder: YearLedgerBuilder
    private let reportActivityFormatter: DateFormatter
    private var stagedEvidenceURLs: [UUID: URL] = [:]
    private var reportActivities: [Int: [ManualReportFormat: ReportActivityState]] = [:]

    public init(
        manager: any ManualEntryManaging,
        exporter: any YearExporting,
        yearDataProvider: any YearDataProviding,
        calendar: Calendar = .current,
    ) {
        self.manager = manager
        self.exporter = exporter
        self.yearDataProvider = yearDataProvider
        ledgerBuilder = YearLedgerBuilder(calendar: calendar)

        reportActivityFormatter = DateFormatter()
        reportActivityFormatter.calendar = calendar
        reportActivityFormatter.locale = Locale(identifier: "en_US_POSIX")
        reportActivityFormatter.dateStyle = .medium
        reportActivityFormatter.timeStyle = .short
    }

    public func load(for year: Int) async {
        isLoading = true
        await refreshRecords(for: year)
        isLoading = false
    }

    public func save(_ draft: ManualEntryDraft, year: Int) async {
        isLoading = true
        _ = await manager.save(draft)
        await refreshRecords(for: year)
        isLoading = false
    }

    public func deleteEntry(id: UUID, year: Int) async {
        isLoading = true
        await manager.deleteEntry(id: id)
        await refreshRecords(for: year)
        isLoading = false
    }

    public func importEvidence(
        manualEntryID: UUID,
        fileURL: URL,
        year: Int,
    ) async {
        isLoading = true

        if await manager.importEvidence(manualEntryID: manualEntryID, fileURL: fileURL) == nil {
            errorMessage = "Could not import the selected evidence file."
        }

        await refreshRecords(for: year)
        isLoading = false
    }

    public func deleteEvidence(
        _ attachment: EvidenceAttachment,
        year: Int,
    ) async {
        isLoading = true
        await manager.deleteEvidence(attachment)
        stagedEvidenceURLs[attachment.id] = nil
        await refreshRecords(for: year)
        isLoading = false
    }

    public func prepareEvidencePreview(for attachment: EvidenceAttachment) async {
        isLoading = true
        defer { isLoading = false }

        guard let url = await stagedEvidenceURL(for: attachment) else {
            errorMessage = "Could not open the selected evidence file."
            return
        }

        previewURL = url
    }

    public func prepareEvidenceShare(for attachment: EvidenceAttachment) async {
        isLoading = true
        defer { isLoading = false }

        guard let url = await stagedEvidenceURL(for: attachment) else {
            errorMessage = "Could not prepare the selected evidence file for sharing."
            return
        }

        shareURL = url
    }

    public func loadInlineEvidenceIfNeeded(for attachment: EvidenceAttachment) async {
        guard attachment.contentType.hasPrefix("image/") else {
            return
        }

        _ = await stagedEvidenceURL(for: attachment)
    }

    public func inlineEvidenceURL(for attachment: EvidenceAttachment) -> URL? {
        stagedEvidenceURLs[attachment.id]
    }

    public func reportActivity(for year: Int, format: ManualReportFormat) -> ReportActivityState? {
        reportActivities[year]?[format]
    }

    public func reportStatusText(for year: Int, format: ManualReportFormat) -> String? {
        guard let activity = reportActivity(for: year, format: format) else {
            return nil
        }

        return "Last \(activity.triggerDescription) \(reportActivityFormatter.string(from: activity.generatedAt))"
    }

    public func preparePlainTextExport(for year: Int) async {
        let bundle = await exporter.exportBundle(for: year)
        plainTextExportDocument = PlainTextExportDocument(text: bundle.plaintext)
        plainTextFilename = bundle.plaintextFilename.replacingOccurrences(of: ".txt", with: "")
        updateReportActivity(
            for: year,
            format: .plainText,
            generatedAt: bundle.generatedAt,
            triggerDescription: "prepared for save on",
        )
    }

    public func preparePDFExport(for year: Int) async {
        let bundle = await exporter.exportBundle(for: year)
        pdfExportDocument = PDFExportDocument(data: bundle.pdfData)
        pdfFilename = bundle.pdfFilename.replacingOccurrences(of: ".pdf", with: "")
        updateReportActivity(
            for: year,
            format: .pdf,
            generatedAt: bundle.generatedAt,
            triggerDescription: "prepared for save on",
        )
    }

    public func preparePlainTextShare(for year: Int) async {
        isLoading = true
        defer { isLoading = false }

        let bundle = await exporter.exportBundle(for: year)
        if stageShareFile(
            filename: bundle.plaintextFilename,
            data: Data(bundle.plaintext.utf8),
            failureMessage: "Could not prepare the text report for sharing.",
        ) {
            updateReportActivity(
                for: year,
                format: .plainText,
                generatedAt: bundle.generatedAt,
                triggerDescription: "prepared for sharing on",
            )
        }
    }

    public func preparePDFShare(for year: Int) async {
        isLoading = true
        defer { isLoading = false }

        let bundle = await exporter.exportBundle(for: year)
        if stageShareFile(
            filename: bundle.pdfFilename,
            data: bundle.pdfData,
            failureMessage: "Could not prepare the PDF report for sharing.",
        ) {
            updateReportActivity(
                for: year,
                format: .pdf,
                generatedAt: bundle.generatedAt,
                triggerDescription: "prepared for sharing on",
            )
        }
    }

    public func clearPlainTextExport() {
        plainTextExportDocument = nil
    }

    public func clearPDFExport() {
        pdfExportDocument = nil
    }

    public func clearPreview() {
        previewURL = nil
    }

    public func clearShare() {
        shareURL = nil
    }

    public func clearError() {
        errorMessage = nil
    }

    private func refreshRecords(for year: Int) async {
        async let recordsTask = manager.records(in: year)
        async let bundleTask = yearDataProvider.bundle(for: year)
        let records = await recordsTask
        let bundle = await bundleTask
        self.records = records
        daySections = makeDaySections(records: records, bundle: bundle)

        let validAttachmentIDs = Set(records.flatMap(\.attachments).map(\.id))
        stagedEvidenceURLs = stagedEvidenceURLs.filter { validAttachmentIDs.contains($0.key) }
    }

    private func stagedEvidenceURL(for attachment: EvidenceAttachment) async -> URL? {
        if let cachedURL = stagedEvidenceURLs[attachment.id] {
            return cachedURL
        }

        guard let url = await manager.evidenceFileURL(for: attachment) else {
            return nil
        }

        stagedEvidenceURLs[attachment.id] = url
        return url
    }

    private func stageShareFile(
        filename: String,
        data: Data,
        failureMessage: String,
    ) -> Bool {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WhereShares")

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil,
            )
            let fileURL = directory.appending(path: filename)
            try data.write(to: fileURL, options: .atomic)
            shareURL = fileURL
            return true
        } catch {
            errorMessage = failureMessage
            return false
        }
    }

    private func makeDaySections(
        records: [ManualEntryRecord],
        bundle: YearDataBundle,
    ) -> [ManualEntryDaySection] {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let ledgers = ledgerBuilder.makeLedgers(
            year: bundle.year,
            samples: bundle.locationSamples,
            manualEntries: bundle.manualEntries,
        )

        return ledgers
            .filter { !$0.manualEntries.isEmpty }
            .sorted { $0.date > $1.date }
            .map { ledger in
                ManualEntryDaySection(
                    date: ledger.date,
                    trackedJurisdictions: ledger.trackedJurisdictions,
                    finalJurisdictions: ledger.finalJurisdictions,
                    note: ledger.note,
                    changesTrackedOutcome: Set(ledger.trackedJurisdictions) != Set(ledger.finalJurisdictions),
                    entries: ledger.manualEntries
                        .sorted { $0.timestamp > $1.timestamp }
                        .map { entry in
                            ManualEntryDayRecord(
                                record: recordsByID[entry.id] ?? ManualEntryRecord(entry: entry, attachments: []),
                                changesDayOutcome: changesDayOutcome(for: entry, in: ledger),
                            )
                        },
                )
            }
    }

    private func changesDayOutcome(
        for entry: ManualLogEntry,
        in ledger: DailyStateLedger,
    ) -> Bool {
        let withEntry = ledgerBuilder.finalJurisdictions(
            trackedJurisdictions: ledger.trackedJurisdictions,
            manualEntries: ledger.manualEntries,
        )
        let withoutEntry = ledgerBuilder.finalJurisdictions(
            trackedJurisdictions: ledger.trackedJurisdictions,
            manualEntries: ledger.manualEntries.filter { $0.id != entry.id },
        )

        return withEntry != withoutEntry
    }

    private func updateReportActivity(
        for year: Int,
        format: ManualReportFormat,
        generatedAt: Date,
        triggerDescription: String,
    ) {
        var yearActivities = reportActivities[year, default: [:]]
        yearActivities[format] = ReportActivityState(
            generatedAt: generatedAt,
            triggerDescription: triggerDescription,
        )
        reportActivities[year] = yearActivities
    }
}
