import PDFKit
import RegionKit
import Testing
import UIKit
import WhereCore
@testable import WhereUI

struct YearPDFRendererTests {
    @Test func standardReportHasMetadataOrderedSectionsPortraitPagesAndSearchableText(
    ) async throws {
        let input = YearPDFTestSupport.document(includeRawGPS: false)
        let file = try await YearPDFRenderer().render(document: input) { _ in }
        defer { try? FileManager.default.removeItem(at: file.storageDirectory) }
        let pdf = try #require(PDFDocument(url: file.url))

        #expect(pdf.pageCount == file.pageCount)
        #expect(pdf.pageCount >= 7)
        let attributes = pdf.documentAttributes
        #expect(
            attributes?[PDFDocumentAttribute.titleAttribute] as? String
                == "Where Presence Report 2024",
        )
        #expect(
            (attributes?[PDFDocumentAttribute.subjectAttribute] as? String)?.contains("2024")
                == true,
        )
        #expect(attributes?[PDFDocumentAttribute.creatorAttribute] as? String == "Where 3.4")
        #expect(attributes?[PDFDocumentAttribute.creationDateAttribute] as? Date != nil)
        #expect(
            (attributes?[PDFDocumentAttribute.keywordsAttribute] as? [String])?.contains(
                "WhereReportID=20000000-0000-0000-0000-000000000002",
            ) == true,
        )

        let text = pdfText(pdf)
        let sections = [
            "Coverage Summary",
            "Regional Totals",
            "Daily Presence Table",
            "Manual-Entry Audit",
            "Evidence Index",
            "Methodology and Limitations",
        ]
        let offsets = try sections.map { section in
            try #require(text.range(of: section)?.lowerBound)
        }
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 < $1 })
        #expect(!text.contains("Raw Device-GPS Appendix"))
        #expect(!text.contains("00000000-0000-0000-0000-000000000001"))

        for index in 0 ..< pdf.pageCount {
            let page = try #require(pdf.page(at: index))
            let bounds = page.bounds(for: .mediaBox)
            #expect(bounds.height > bounds.width)
            #expect(page.string?.contains("Page \(index + 1) of \(pdf.pageCount)") == true)
        }
    }

    @Test func rawAppendixUsesLandscapeAndContainsEveryGPSUUIDExactlyOnce() async throws {
        let input = YearPDFTestSupport.document(includeRawGPS: true, gpsCount: 1000)
        let recorder = ProgressRecorder()
        let file = try await YearPDFRenderer().render(document: input) { update in
            recorder.append(update)
        }
        defer { try? FileManager.default.removeItem(at: file.storageDirectory) }
        let pdf = try #require(PDFDocument(url: file.url))

        #expect(recorder.values.first?.completedPages == 0)
        #expect(recorder.values.last == YearPDFProgress(
            completedPages: pdf.pageCount,
            totalPages: pdf.pageCount,
        ))
        let pageOrientations = (0 ..< pdf.pageCount).map {
            pdf.page(at: $0)!.bounds(for: .mediaBox)
        }
        #expect(pageOrientations.contains { $0.width > $0.height })
        #expect(pageOrientations.prefix { $0.height > $0.width }.count >= 7)

        let compactText = pdfText(pdf).filter { !$0.isWhitespace }
        let expression = try NSRegularExpression(
            pattern: "00000000-0000-0000-0000-[0-9]{12}",
        )
        let range = NSRange(compactText.startIndex..., in: compactText)
        let matches = expression.matches(in: compactText, range: range).compactMap {
            Range($0.range, in: compactText).map { String(compactText[$0]) }
        }
        #expect(matches.count == 1000)
        #expect(Set(matches).count == 1000)
        #expect(compactText.contains("gpsVisit"))
        #expect(compactText.contains("gpsSignificantChange"))
        #expect(compactText.contains("37.774900"))
        #expect(compactText.contains("-122.419400"))
        #expect(compactText.contains("7m"))
    }

    @Test func demoReportWatermarksEveryPageAndUsesDemoMetadataAndFilename() async throws {
        let file = try await YearPDFRenderer().render(
            document: YearPDFTestSupport.document(isDemo: true),
        ) { _ in }
        defer { try? FileManager.default.removeItem(at: file.storageDirectory) }
        let pdf = try #require(PDFDocument(url: file.url))

        #expect(file.suggestedFilename.hasPrefix("Where Demo Presence Report 2024 "))
        #expect(
            (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.hasPrefix(
                "SAMPLE — DEMO DATA",
            ) == true,
        )
        for index in 0 ..< pdf.pageCount {
            #expect(pdf.page(at: index)?.string?.contains("SAMPLE — DEMO DATA") == true)
        }
    }

    @Test func a4LongUnicodeContentRendersEveryPageWithoutBlankOutput() async throws {
        let longNote = String(
            repeating: "Réservation 東京 - supporting note with wrapped words. ",
            count: 150,
        )
        let file = try await YearPDFRenderer().render(
            document: YearPDFTestSupport.document(pageSize: .a4, note: longNote),
        ) { _ in }
        defer { try? FileManager.default.removeItem(at: file.storageDirectory) }
        let pdf = try #require(PDFDocument(url: file.url))

        #expect(abs((pdf.page(at: 0)?.bounds(for: .mediaBox).width ?? 0) - 595.28) < 0.1)
        #expect(pdfText(pdf).contains("Réservation 東京"))
        for index in 0 ..< pdf.pageCount {
            let page = try #require(pdf.page(at: index))
            #expect(!(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let thumbnail = page.thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox)
            #expect((thumbnail.pngData()?.count ?? 0) > 1000)
        }
    }

    @Test func emptyReportStillRendersEveryRequiredMainSection() async throws {
        let base = YearPDFTestSupport.document()
        let emptyAudit = YearAuditReport(
            report: YearReport(year: 2024, days: [], totals: [:]),
            samples: [],
            manualDays: [],
            evidence: [],
            trackedRegions: base.audit.trackedRegions,
            timeZone: base.audit.timeZone,
            regionDataSources: base.audit.regionDataSources,
        )
        let file = try await YearPDFRenderer().render(
            document: replacingAudit(in: base, with: emptyAudit),
        ) { _ in }
        defer { try? FileManager.default.removeItem(at: file.storageDirectory) }
        let pdf = try #require(PDFDocument(url: file.url))
        let text = pdfText(pdf)

        #expect(pdf.pageCount == 7)
        #expect(text.contains("Coverage Summary"))
        #expect(text.contains("Daily Presence Table"))
        #expect(text.contains("Manual-Entry Audit"))
        #expect(text.contains("Evidence Index"))
        #expect(text.contains("Methodology and Limitations"))
    }

    @Test func contiguousIdenticalManualRecordsConsolidateWithoutLosingSeparatedDates(
    ) async throws {
        let base = YearPDFTestSupport.document()
        let audit = ManualEntryAudit(
            recordedAt: YearPDFTestSupport.date("2024-04-01T10:00:00-07:00"),
            note: "Shared audit note",
            location: nil,
        )
        let manualDays = [1, 2, 4].map {
            DayPresence(
                day: CalendarDay(year: 2024, month: 3, day: $0),
                regions: [.california],
                audit: audit,
            )
        }
        let groupedAudit = YearAuditReport(
            report: base.audit.report,
            samples: base.audit.samples,
            manualDays: manualDays,
            evidence: base.audit.evidence,
            trackedRegions: base.audit.trackedRegions,
            timeZone: base.audit.timeZone,
            regionDataSources: base.audit.regionDataSources,
        )
        let file = try await YearPDFRenderer().render(
            document: replacingAudit(in: base, with: groupedAudit),
        ) { _ in }
        defer { try? FileManager.default.removeItem(at: file.storageDirectory) }
        let pdf = try #require(PDFDocument(url: file.url))
        let text = pdfText(pdf).replacingOccurrences(of: "\n", with: " ")

        #expect(text.contains("2024-03-01 - 2024-03-02"))
        #expect(text.contains("2024-03-04"))
        #expect(text.components(separatedBy: "Shared audit note").count - 1 == 2)
    }

    private func pdfText(_ pdf: PDFDocument) -> String {
        (0 ..< pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private func replacingAudit(
        in document: YearPDFDocument,
        with audit: YearAuditReport,
    ) -> YearPDFDocument {
        YearPDFDocument(
            audit: audit,
            generatedAt: document.generatedAt,
            reportID: document.reportID,
            preparedFor: document.preparedFor,
            reference: document.reference,
            pageSize: document.pageSize,
            includeRawGPS: document.includeRawGPS,
            isDemo: document.isDemo,
            buildInfo: document.buildInfo,
        )
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [YearPDFProgress] = []

    var values: [YearPDFProgress] {
        lock.withLock { storage }
    }

    func append(_ value: YearPDFProgress) {
        lock.withLock { storage.append(value) }
    }
}
