import Foundation
import UniformTypeIdentifiers
import WhereCore

public actor ManualDataImportController: ManualDataImporting {
    private let calendar: Calendar
    private let manualEntryRepository: any ManualLogEntryRepository
    private let manualEntryController: ManualEntryController
    private let evidenceController: EvidenceController
    private let manifestDecoder: JSONDecoder

    public init(
        calendar: Calendar = .current,
        manualEntryRepository: any ManualLogEntryRepository,
        manualEntryController: ManualEntryController,
        evidenceController: EvidenceController,
    ) {
        self.calendar = calendar
        self.manualEntryRepository = manualEntryRepository
        self.manualEntryController = manualEntryController
        self.evidenceController = evidenceController

        manifestDecoder = JSONDecoder()
        manifestDecoder.dateDecodingStrategy = .iso8601
    }

    public func previewBackfill(_ request: ManualImportBackfillRequest) async -> ManualImportPreview {
        let normalizedStart = calendar.startOfDay(for: request.startDate)
        let normalizedEnd = calendar.startOfDay(for: request.endDate)

        guard normalizedStart <= normalizedEnd else {
            return ManualImportPreview(
                yearSpan: nil,
                entryCount: 0,
                evidenceAttachmentCount: 0,
                sharedEvidenceAttachmentCount: 0,
                entries: [],
                issues: [
                    .init(
                        severity: .error,
                        message: "The end date must be on or after the start date.",
                    ),
                ],
            )
        }

        var entries: [ManualImportEntryDraft] = []
        var currentDate = normalizedStart

        while currentDate <= normalizedEnd {
            let timestamp = midday(for: currentDate)
            entries.append(
                ManualImportEntryDraft(
                    timestamp: timestamp,
                    jurisdiction: request.jurisdiction,
                    note: request.note,
                    kind: request.kind,
                    evidenceFiles: request.evidenceFiles,
                ),
            )

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDay
        }

        return ManualImportPreview(
            yearSpan: yearSpan(for: entries.map(\.timestamp)),
            entryCount: entries.count,
            evidenceAttachmentCount: entries.reduce(0) { $0 + $1.evidenceFiles.count },
            sharedEvidenceAttachmentCount: request.evidenceFiles.count,
            entries: entries,
        )
    }

    public func previewPackage(at directoryURL: URL) async -> ManualImportPreview {
        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        return previewPackageUnlocked(at: directoryURL)
    }

    public func importEntries(_ entries: [ManualImportEntryDraft]) async -> [ManualEntryRecord] {
        guard !entries.isEmpty else {
            return []
        }

        let manualEntries = entries.map(\.manualLogEntry)
        await manualEntryRepository.save(manualEntries)

        do {
            let evidenceRequests = try makeEvidenceRequests(for: entries)
            _ = try await evidenceController.importEvidence(evidenceRequests)
        } catch {
            for manualEntry in manualEntries {
                await manualEntryRepository.delete(id: manualEntry.id)
            }
            return []
        }

        let importedIDs = Set(manualEntries.map(\.id))
        let years = Set(manualEntries.map { calendar.component(.year, from: $0.timestamp) })

        var records: [ManualEntryRecord] = []
        for year in years.sorted() {
            let yearRecords = await manualEntryController.records(in: year)
            records.append(contentsOf: yearRecords.filter { importedIDs.contains($0.id) })
        }

        return records.sorted { lhs, rhs in
            if lhs.entry.timestamp == rhs.entry.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.entry.timestamp < rhs.entry.timestamp
        }
    }

    public func importPackage(at directoryURL: URL) async -> [ManualEntryRecord] {
        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        let preview = previewPackageUnlocked(at: directoryURL)
        guard preview.isValid else {
            return []
        }

        return await importEntries(preview.entries)
    }

    private func previewPackageUnlocked(at directoryURL: URL) -> ManualImportPreview {
        let manifestURL = directoryURL.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return ManualImportPreview(
                yearSpan: nil,
                entryCount: 0,
                evidenceAttachmentCount: 0,
                sharedEvidenceAttachmentCount: 0,
                entries: [],
                issues: [
                    .init(
                        severity: .error,
                        message: "The selected package is missing `manifest.json`.",
                    ),
                ],
            )
        }

        let manifest: ManualImportPackageManifest
        do {
            manifest = try manifestDecoder.decode(ManualImportPackageManifest.self, from: data)
        } catch {
            return ManualImportPreview(
                yearSpan: nil,
                entryCount: 0,
                evidenceAttachmentCount: 0,
                sharedEvidenceAttachmentCount: 0,
                entries: [],
                issues: [
                    .init(
                        severity: .error,
                        message: "The selected manifest could not be decoded.",
                    ),
                ],
            )
        }

        let evidenceDirectory = directoryURL.appending(path: "evidence")
        var entries: [ManualImportEntryDraft] = []
        var issues: [ManualImportPreview.Issue] = []
        var evidenceAttachmentCount = 0

        for manifestEntry in manifest.entries {
            guard let jurisdiction = manifestEntry.jurisdiction.resolve() else {
                issues.append(
                    .init(
                        severity: .error,
                        message: "Unsupported jurisdiction code `\(manifestEntry.jurisdiction.displayValue)`.",
                    ),
                )
                continue
            }

            var evidenceFiles: [URL] = []
            for filename in manifestEntry.evidenceFilenames {
                let candidateURL = evidenceDirectory.appending(path: filename)
                if FileManager.default.fileExists(atPath: candidateURL.path) {
                    evidenceFiles.append(candidateURL)
                } else {
                    issues.append(
                        .init(
                            severity: .error,
                            message: "Missing evidence file `\(filename)` referenced by the manifest.",
                        ),
                    )
                }
            }

            evidenceAttachmentCount += manifestEntry.evidenceFilenames.count
            entries.append(
                ManualImportEntryDraft(
                    timestamp: manifestEntry.timestamp,
                    jurisdiction: jurisdiction,
                    note: manifestEntry.note ?? "",
                    kind: manifestEntry.kind,
                    evidenceFiles: evidenceFiles,
                ),
            )
        }

        let years = Set(entries.map { calendar.component(.year, from: $0.timestamp) })
        if years.count > 1, let lowerBound = years.min(), let upperBound = years.max() {
            issues.append(
                .init(
                    severity: .warning,
                    message: "This package spans multiple years (\(lowerBound)-\(upperBound)).",
                ),
            )
        }

        return ManualImportPreview(
            yearSpan: yearSpan(for: entries.map(\.timestamp)),
            entryCount: entries.count,
            evidenceAttachmentCount: evidenceAttachmentCount,
            sharedEvidenceAttachmentCount: countSharedEvidenceFiles(in: entries),
            entries: entries,
            issues: issues,
        )
    }

    private func makeEvidenceRequests(
        for entries: [ManualImportEntryDraft],
    ) throws -> [(manualEntryID: UUID, originalFilename: String, contentType: String, data: Data, createdAt: Date)] {
        try entries.flatMap { entry in
            try entry.evidenceFiles.map { fileURL in
                let data = try Data(contentsOf: fileURL)
                let resourceValues = try? fileURL.resourceValues(forKeys: [.contentTypeKey, .nameKey])
                let contentType = resourceValues?.contentType?.preferredMIMEType
                    ?? UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let originalFilename = resourceValues?.name ?? fileURL.lastPathComponent

                return (
                    manualEntryID: entry.id,
                    originalFilename: originalFilename,
                    contentType: contentType,
                    data: data,
                    createdAt: entry.timestamp,
                )
            }
        }
    }

    private func midday(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: components.year,
                month: components.month,
                day: components.day,
                hour: 12,
            ),
        ) ?? date
    }

    private func yearSpan(for dates: [Date]) -> ClosedRange<Int>? {
        let years = dates.map { calendar.component(.year, from: $0) }
        guard let minYear = years.min(), let maxYear = years.max() else {
            return nil
        }

        return minYear ... maxYear
    }

    private func countSharedEvidenceFiles(in entries: [ManualImportEntryDraft]) -> Int {
        let counts = Dictionary(grouping: entries.flatMap(\.evidenceFiles), by: \.standardizedFileURL)
        return counts.values.count(where: { $0.count > 1 })
    }
}
