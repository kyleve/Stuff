import Foundation
import WhereCore

public actor YearExportController: YearExporting {
    private let calendar: Calendar
    private let yearDataProvider: any YearDataProviding
    private let ledgerBuilder: YearLedgerBuilder
    private let generatedAt: @Sendable () -> Date
    private let timestampFormatter: DateFormatter
    private let dayFormatter: DateFormatter

    public init(
        calendar: Calendar = .current,
        yearDataProvider: any YearDataProviding,
        generatedAt: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.calendar = calendar
        self.yearDataProvider = yearDataProvider
        ledgerBuilder = YearLedgerBuilder(calendar: calendar)
        self.generatedAt = generatedAt

        timestampFormatter = DateFormatter()
        timestampFormatter.calendar = calendar
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"

        dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
    }

    public func exportBundle(for year: Int) async -> YearExportBundle {
        let bundle = await yearDataProvider.bundle(for: year)
        let ledgers = ledgerBuilder.makeLedgers(
            year: year,
            samples: bundle.locationSamples,
            manualEntries: bundle.manualEntries,
        )
        let summary = ledgerBuilder.makeYearSummary(year: year, ledgers: ledgers)
        let manualRecords = manualRecords(
            from: bundle.manualEntries,
            evidenceAttachments: bundle.evidenceAttachments,
        )
        let generatedAt = generatedAt()
        let plaintext = plaintextExport(
            year: year,
            summary: summary,
            ledgers: ledgers,
            manualRecords: manualRecords,
            generatedAt: generatedAt,
            trackingState: bundle.trackingState,
        )

        return YearExportBundle(
            year: year,
            generatedAt: generatedAt,
            plaintext: plaintext,
            pdfData: pdfData(
                year: year,
                summary: summary,
                ledgers: ledgers,
                manualRecords: manualRecords,
                generatedAt: generatedAt,
                trackingState: bundle.trackingState,
            ),
        )
    }

    private func manualRecords(
        from entries: [ManualLogEntry],
        evidenceAttachments: [EvidenceAttachment],
    ) -> [ManualEntryRecord] {
        let attachmentsByEntryID = Dictionary(grouping: evidenceAttachments, by: \.manualEntryID)

        return entries
            .sorted { $0.timestamp < $1.timestamp }
            .map { entry in
                ManualEntryRecord(
                    entry: entry,
                    attachments: attachmentsByEntryID[entry.id, default: []]
                        .sorted { $0.createdAt < $1.createdAt },
                )
            }
    }

    private func plaintextExport(
        year: Int,
        summary: YearSummary,
        ledgers: [DailyStateLedger],
        manualRecords: [ManualEntryRecord],
        generatedAt: Date,
        trackingState: TrackingState?,
    ) -> String {
        var lines = [
            "Where Tax Report",
            "Year: \(year)",
            "Generated: \(timestampFormatter.string(from: generatedAt))",
        ]

        if let trackingState {
            lines.append("Tracking status: \(trackingState.runtimeStatus(at: generatedAt).title)")
        }

        lines += [
            "",
            "Totals",
        ]

        let orderedTotals = summary.totalsByJurisdiction
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.displayName < rhs.key.displayName
                }

                return lhs.value > rhs.value
            }

        for (jurisdiction, totalDays) in orderedTotals {
            lines.append("- \(jurisdiction.displayName): \(totalDays) day(s)")
        }

        lines += [
            "- Unknown: \(summary.unknownDayCount) day(s)",
            "- Total tracked days: \(summary.totalTrackedDays)",
            "",
            "Daily Ledger",
        ]

        if ledgers.isEmpty {
            lines.append("- No daily ledger entries")
        } else {
            for ledger in ledgers {
                let jurisdictions = ledger.finalJurisdictions.map(\.displayName).joined(separator: ", ")
                let noteSuffix = ledger.note.map { " | \($0)" } ?? ""
                lines.append("- \(dayFormatter.string(from: ledger.date)): \(jurisdictions)\(noteSuffix)")
            }
        }

        lines += [
            "",
            "Manual Entries",
        ]

        if manualRecords.isEmpty {
            lines.append("- No manual entries")
        } else {
            for record in manualRecords {
                let entry = record.entry
                let noteSuffix = entry.note.map { " | \($0)" } ?? ""
                lines.append(
                    "- \(timestampFormatter.string(from: entry.timestamp)) | \(entry.kind.rawValue.capitalized) | \(entry.jurisdiction.displayName)\(noteSuffix)",
                )

                if record.attachments.isEmpty {
                    lines.append("  Evidence: none")
                } else {
                    for attachment in record.attachments {
                        lines.append(
                            "  Evidence: \(attachment.originalFilename) (\(attachment.contentType), \(attachment.byteCount) bytes)",
                        )
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func pdfData(
        year: Int,
        summary: YearSummary,
        ledgers: [DailyStateLedger],
        manualRecords: [ManualEntryRecord],
        generatedAt: Date,
        trackingState: TrackingState?,
    ) -> Data {
        var pageStreams: [String] = []
        var pageText = ""
        var cursorY: Double = 742

        func startPage() {
            pageText = ""
            cursorY = 742
        }

        func commitPage() {
            let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pageStreams.append(trimmed)
            }
        }

        func ensureSpace(_ requiredHeight: Double) {
            if cursorY - requiredHeight < 50 {
                commitPage()
                startPage()
            }
        }

        func appendText(_ text: String, x: Double, font: String, size: Double) {
            pageText += "BT\n/\(font) \(size) Tf\n1 0 0 1 \(pdfNumber(x)) \(pdfNumber(cursorY)) Tm\n(\(escapedPDFText(text))) Tj\nET\n"
        }

        func appendWrappedText(
            _ text: String,
            x: Double,
            font: String,
            size: Double,
            lineHeight: Double,
            width: Int,
        ) {
            let lines = wrappedLines(for: text, maxCharacters: width)
            ensureSpace(Double(lines.count) * lineHeight)

            for line in lines {
                appendText(line, x: x, font: font, size: size)
                cursorY -= lineHeight
            }
        }

        func appendSpacer(_ amount: Double) {
            cursorY -= amount
        }

        startPage()

        appendText("Where Tax Report", x: 50, font: "F2", size: 22)
        cursorY -= 28
        appendText("Year \(year)", x: 50, font: "F2", size: 16)
        cursorY -= 22
        appendText("Generated \(timestampFormatter.string(from: generatedAt))", x: 50, font: "F1", size: 11)
        cursorY -= 18

        if let trackingState {
            appendText("Tracking status: \(trackingState.runtimeStatus(at: generatedAt).title)", x: 50, font: "F1", size: 11)
            cursorY -= 22
        } else {
            cursorY -= 4
        }

        ensureSpace(24)
        appendText("Totals", x: 50, font: "F2", size: 14)
        cursorY -= 20

        let orderedTotals = summary.totalsByJurisdiction
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.displayName < rhs.key.displayName
                }

                return lhs.value > rhs.value
            }

        for (jurisdiction, totalDays) in orderedTotals {
            appendWrappedText(
                "\(jurisdiction.displayName): \(totalDays) day(s)",
                x: 64,
                font: "F1",
                size: 11,
                lineHeight: 14,
                width: 62,
            )
        }

        appendWrappedText(
            "Unknown: \(summary.unknownDayCount) day(s)",
            x: 64,
            font: "F1",
            size: 11,
            lineHeight: 14,
            width: 62,
        )
        appendWrappedText(
            "Total tracked days: \(summary.totalTrackedDays)",
            x: 64,
            font: "F1",
            size: 11,
            lineHeight: 14,
            width: 62,
        )
        appendSpacer(10)

        ensureSpace(24)
        appendText("Daily Ledger", x: 50, font: "F2", size: 14)
        cursorY -= 20

        if ledgers.isEmpty {
            appendWrappedText(
                "No daily ledger entries",
                x: 64,
                font: "F1",
                size: 11,
                lineHeight: 14,
                width: 62,
            )
        } else {
            for ledger in ledgers {
                let jurisdictions = ledger.finalJurisdictions.map(\.displayName).joined(separator: ", ")
                appendWrappedText(
                    "\(dayFormatter.string(from: ledger.date))  \(jurisdictions)",
                    x: 64,
                    font: "F1",
                    size: 11,
                    lineHeight: 14,
                    width: 62,
                )

                if let note = ledger.note {
                    appendWrappedText(
                        note,
                        x: 80,
                        font: "F1",
                        size: 10,
                        lineHeight: 13,
                        width: 56,
                    )
                }

                appendSpacer(4)
            }
        }

        ensureSpace(24)
        appendText("Manual Entries", x: 50, font: "F2", size: 14)
        cursorY -= 20

        if manualRecords.isEmpty {
            appendWrappedText(
                "No manual entries",
                x: 64,
                font: "F1",
                size: 11,
                lineHeight: 14,
                width: 62,
            )
        } else {
            for record in manualRecords {
                let entry = record.entry
                appendWrappedText(
                    "\(timestampFormatter.string(from: entry.timestamp))",
                    x: 64,
                    font: "F2",
                    size: 11,
                    lineHeight: 14,
                    width: 62,
                )
                appendWrappedText(
                    "\(entry.kind.rawValue.capitalized) - \(entry.jurisdiction.displayName)",
                    x: 80,
                    font: "F1",
                    size: 11,
                    lineHeight: 14,
                    width: 56,
                )

                if let note = entry.note {
                    appendWrappedText(
                        note,
                        x: 80,
                        font: "F1",
                        size: 10,
                        lineHeight: 13,
                        width: 56,
                    )
                }

                if record.attachments.isEmpty {
                    appendWrappedText(
                        "Evidence: none",
                        x: 80,
                        font: "F1",
                        size: 10,
                        lineHeight: 13,
                        width: 56,
                    )
                } else {
                    for attachment in record.attachments {
                        appendWrappedText(
                            "Evidence: \(attachment.originalFilename) (\(attachment.contentType), \(attachment.byteCount) bytes)",
                            x: 80,
                            font: "F1",
                            size: 10,
                            lineHeight: 13,
                            width: 56,
                        )
                    }
                }

                appendSpacer(8)
            }
        }

        commitPage()

        if pageStreams.isEmpty {
            pageStreams = ["BT\n/F2 18 Tf\n1 0 0 1 50 742 Tm\n(Where Tax Report) Tj\nET"]
        }

        return makePDFDocument(pageStreams: pageStreams)
    }

    private func makePDFDocument(pageStreams: [String]) -> Data {
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>",
        ]
        var pageObjectNumbers: [Int] = []

        for stream in pageStreams {
            let pageObjectNumber = objects.count + 1
            let contentObjectNumber = pageObjectNumber + 1
            pageObjectNumbers.append(pageObjectNumber)

            objects.append(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents \(contentObjectNumber) 0 R >>",
            )
            objects.append(
                """
                << /Length \(stream.utf8.count) >>
                stream
                \(stream)
                endstream
                """,
            )
        }

        objects[1] = "<< /Type /Pages /Kids [\(pageObjectNumbers.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(pageObjectNumbers.count) >>"

        var pdf = "%PDF-1.4\n"
        var offsets = [0]

        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }

        let xrefOffset = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n"
        pdf += "0000000000 65535 f \n"

        for offset in offsets.dropFirst() {
            pdf += String(format: "%010d 00000 n \n", offset)
        }

        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\n"
        pdf += "startxref\n\(xrefOffset)\n%%EOF"
        return Data(pdf.utf8)
    }

    private func wrappedLines(for text: String, maxCharacters: Int) -> [String] {
        guard !text.isEmpty else {
            return [""]
        }

        var lines: [String] = []

        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let words = paragraph.split(separator: " ", omittingEmptySubsequences: true)

            if words.isEmpty {
                lines.append("")
                continue
            }

            var currentLine = ""

            for word in words {
                let candidate = currentLine.isEmpty ? String(word) : "\(currentLine) \(word)"

                if candidate.count <= maxCharacters {
                    currentLine = candidate
                } else {
                    if !currentLine.isEmpty {
                        lines.append(currentLine)
                    }

                    currentLine = String(word)

                    while currentLine.count > maxCharacters {
                        let splitIndex = currentLine.index(currentLine.startIndex, offsetBy: maxCharacters)
                        lines.append(String(currentLine[..<splitIndex]))
                        currentLine = String(currentLine[splitIndex...])
                    }
                }
            }

            if !currentLine.isEmpty {
                lines.append(currentLine)
            }
        }

        return lines
    }

    private func pdfNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func escapedPDFText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
}
