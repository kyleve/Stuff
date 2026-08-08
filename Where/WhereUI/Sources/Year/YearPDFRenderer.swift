import CoreGraphics
import Foundation
import RegionKit
import UIKit
import WhereCore

struct YearPDFProgress: Hashable {
    let completedPages: Int
    let totalPages: Int
}

protocol YearPDFRendering: Sendable {
    func render(
        document: YearPDFDocument,
        progress: @escaping @Sendable (YearPDFProgress) -> Void,
    ) async throws -> YearPDFFile
}

/// Deterministic two-pass annual-report renderer. It lays out every page first,
/// then writes searchable text to PDF off the main actor, checking cancellation
/// before each page and removing any partial output on failure.
struct YearPDFRenderer: YearPDFRendering {
    @concurrent
    func render(
        document: YearPDFDocument,
        progress: @escaping @Sendable (YearPDFProgress) -> Void,
    ) async throws -> YearPDFFile {
        try Task.checkCancellation()
        let pages = try Layout.makePages(for: document)
        try Task.checkCancellation()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("where-annual-reports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filename = Self.filename(for: document)
        let url = directory.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = Self.metadata(for: document)
            let renderer = UIGraphicsPDFRenderer(
                bounds: document.pageSize.portraitBounds,
                format: format,
            )
            progress(YearPDFProgress(completedPages: 0, totalPages: pages.count))
            var cancelled = false
            try renderer.writePDF(to: url) { context in
                for (index, page) in pages.enumerated() {
                    guard !Task.isCancelled else {
                        cancelled = true
                        return
                    }
                    context.beginPage(withBounds: page.bounds, pageInfo: [:])
                    page.draw(in: context.cgContext)
                    Self.drawFooter(
                        pageNumber: index + 1,
                        pageCount: pages.count,
                        bounds: page.bounds,
                    )
                    if document.isDemo {
                        Self.drawDemoWatermark(in: page.bounds)
                    }
                    progress(YearPDFProgress(
                        completedPages: index + 1,
                        totalPages: pages.count,
                    ))
                }
            }
            if cancelled || Task.isCancelled {
                throw CancellationError()
            }
            return YearPDFFile(
                url: url,
                storageDirectory: directory,
                suggestedFilename: filename,
                pageCount: pages.count,
            )
        } catch {
            if FileManager.default.fileExists(atPath: directory.path) {
                do {
                    try FileManager.default.removeItem(at: directory)
                } catch {
                    throw PartialOutputCleanupError()
                }
            }
            throw error
        }
    }

    private static func filename(for document: YearPDFDocument) -> String {
        let prefix = document.isDemo
            ? Copy.demoFilenamePrefix
            : Copy.filenamePrefix
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = document.audit.timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(prefix) \(document.audit.report.year) \(formatter.string(from: document.generatedAt)).pdf"
    }

    private static func metadata(for document: YearPDFDocument) -> [String: Any] {
        let year = String(document.audit.report.year)
        let title = document.isDemo
            ? "\(Copy.demoWarning) - \(Copy.reportTitle) \(year)"
            : "\(Copy.reportTitle) \(year)"
        let creatorVersion = document.buildInfo.version.map { " \($0)" } ?? ""
        return [
            kCGPDFContextTitle as String: title,
            kCGPDFContextSubject as String: "\(Copy.subject) \(year)",
            kCGPDFContextCreator as String: "Where\(creatorVersion)",
            kCGPDFContextKeywords as String: "WhereReportID=\(document.reportID.uuidString)",
            "CreationDate": document.generatedAt,
            "WhereReportID": document.reportID.uuidString,
            "WhereDemoData": document.isDemo ? "true" : "false",
        ]
    }

    private static func drawFooter(pageNumber: Int, pageCount: Int, bounds: CGRect) {
        let text = "\(Copy.page) \(pageNumber) \(Copy.of) \(pageCount)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 22),
            withAttributes: attributes,
        )
    }

    private static func drawDemoWatermark(in bounds: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.translateBy(x: bounds.midX, y: bounds.midY)
        context?.rotate(by: -.pi / 5)
        let text = Copy.demoWarning as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: min(bounds.width, bounds.height) / 14),
            .foregroundColor: UIColor.systemRed.withAlphaComponent(0.12),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: -size.width / 2, y: -size.height / 2),
            withAttributes: attributes,
        )
        context?.restoreGState()
    }
}

private struct PartialOutputCleanupError: Error {}

// MARK: - Pre-layout

extension YearPDFRenderer {
    fileprivate struct Layout {
        private static let margin: CGFloat = 44
        private static let footerReserve: CGFloat = 38
        private static let columnGap: CGFloat = 5

        var document: YearPDFDocument
        var pages: [Page] = []
        var pageIndex: Int?
        var cursorY: CGFloat = margin
        var currentSection: String?

        static func makePages(for document: YearPDFDocument) throws -> [Page] {
            var layout = Layout(document: document)
            try layout.cover()
            try layout.coverageSummary()
            try layout.regionalTotals()
            try layout.dailyPresence()
            try layout.manualEntryAudit()
            try layout.evidenceIndex()
            try layout.methodology()
            if document.includeRawGPS {
                try layout.rawGPSAppendix()
            }
            return layout.pages
        }

        private var contentWidth: CGFloat {
            currentPage.bounds.width - Self.margin * 2
        }

        private var contentBottom: CGFloat {
            currentPage.bounds.height - Self.footerReserve
        }

        private var currentPage: Page {
            get { pages[pageIndex!] }
            set { pages[pageIndex!] = newValue }
        }

        private mutating func startPage(
            orientation: Orientation,
            continuedSection: String? = nil,
        ) {
            let bounds = orientation == .portrait
                ? document.pageSize.portraitBounds
                : document.pageSize.landscapeBounds
            pages.append(Page(bounds: bounds, commands: []))
            pageIndex = pages.indices.last
            cursorY = Self.margin
            if let continuedSection {
                addLine(
                    "\(continuedSection) - \(Copy.continued)",
                    style: .runningHeader,
                    color: .secondary,
                )
                cursorY += 5
            }
        }

        private mutating func beginSection(_ title: String, orientation: Orientation = .portrait) {
            currentSection = title
            startPage(orientation: orientation)
            addLine(title, style: .sectionTitle, color: .accent)
            cursorY += 10
        }

        private mutating func ensureSpace(_ height: CGFloat, orientation: Orientation) {
            guard pageIndex != nil else {
                startPage(orientation: orientation)
                return
            }
            let currentOrientation: Orientation = currentPage.bounds.width > currentPage.bounds
                .height
                ? .landscape
                : .portrait
            if currentOrientation != orientation || cursorY + height > contentBottom {
                startPage(orientation: orientation, continuedSection: currentSection)
            }
        }

        private mutating func addLine(
            _ text: String,
            style: TextStyle,
            color: PDFColor = .primary,
            x: CGFloat? = nil,
            width: CGFloat? = nil,
            alignment: NSTextAlignment = .left,
        ) {
            let lineHeight = style.lineHeight
            let rect = CGRect(
                x: x ?? Self.margin,
                y: cursorY,
                width: width ?? contentWidth,
                height: lineHeight,
            )
            currentPage.commands.append(.text(TextCommand(
                text: text,
                rect: rect,
                style: style,
                color: color,
                alignment: alignment,
            )))
            cursorY += lineHeight
        }

        private mutating func paragraph(
            _ text: String,
            style: TextStyle = .body,
            color: PDFColor = .primary,
            spacingAfter: CGFloat = 8,
            orientation: Orientation = .portrait,
        ) {
            let lines = Self.wrap(text, width: contentWidth, style: style)
            for line in lines {
                ensureSpace(style.lineHeight, orientation: orientation)
                addLine(line, style: style, color: color)
            }
            cursorY += spacingAfter
        }

        private mutating func labelValue(
            _ label: String,
            _ value: String,
            orientation: Orientation = .portrait,
        ) {
            let labelWidth: CGFloat = min(132, contentWidth * 0.28)
            let valueWidth = contentWidth - labelWidth - 8
            let labelLines = Self.wrap(label, width: labelWidth, style: .label)
            let valueLines = Self.wrap(value, width: valueWidth, style: .body)
            let lineCount = max(labelLines.count, valueLines.count)
            var lineOffset = 0
            while lineOffset < lineCount {
                let availableHeight = contentBottom - cursorY - 4
                let availableLines = Int(floor(availableHeight / TextStyle.body.lineHeight))
                if availableLines < 1 {
                    startPage(orientation: orientation, continuedSection: currentSection)
                    continue
                }
                let chunkCount = min(availableLines, lineCount - lineOffset)
                let startY = cursorY
                // Repeat the label on a continuation page so a split value does
                // not lose its meaning; the value itself is never truncated.
                let visibleLabel = lineOffset == 0 ? labelLines : ["\(label) - \(Copy.continued)"]
                for (index, line) in visibleLabel.prefix(chunkCount).enumerated() {
                    let rect = CGRect(
                        x: Self.margin,
                        y: startY + CGFloat(index) * TextStyle.body.lineHeight,
                        width: labelWidth,
                        height: TextStyle.body.lineHeight,
                    )
                    currentPage.commands.append(.text(TextCommand(
                        text: line,
                        rect: rect,
                        style: .label,
                        color: .secondary,
                        alignment: .left,
                    )))
                }
                let sliceEnd = min(lineOffset + chunkCount, valueLines.count)
                if lineOffset < sliceEnd {
                    for (index, line) in valueLines[lineOffset ..< sliceEnd].enumerated() {
                        let rect = CGRect(
                            x: Self.margin + labelWidth + 8,
                            y: startY + CGFloat(index) * TextStyle.body.lineHeight,
                            width: valueWidth,
                            height: TextStyle.body.lineHeight,
                        )
                        currentPage.commands.append(.text(TextCommand(
                            text: line,
                            rect: rect,
                            style: .body,
                            color: .primary,
                            alignment: .left,
                        )))
                    }
                }
                cursorY += CGFloat(chunkCount) * TextStyle.body.lineHeight + 4
                lineOffset += chunkCount
            }
        }

        private mutating func table(
            headers: [String],
            widths: [CGFloat],
            rows: [[String]],
            orientation: Orientation = .portrait,
            style: TextStyle = .table,
        ) throws {
            precondition(headers.count == widths.count)
            precondition(rows.allSatisfy { $0.count == headers.count })
            var rowNumber = 0

            func columnFrames(totalWidth: CGFloat) -> [CGRect] {
                let available = totalWidth - Self.columnGap * CGFloat(widths.count - 1)
                var x = Self.margin
                return widths.map { fraction in
                    defer { x += available * fraction + Self.columnGap }
                    return CGRect(x: x, y: 0, width: available * fraction, height: 0)
                }
            }

            let columns = columnFrames(totalWidth: contentWidth)

            func headerHeight() -> CGFloat {
                let counts = zip(headers, columns).map {
                    Self.wrap($0.0, width: $0.1.width - 8, style: .tableHeader).count
                }
                return CGFloat(max(counts.max() ?? 1, 1)) * TextStyle.tableHeader.lineHeight + 8
            }

            func drawHeader() {
                let height = headerHeight()
                ensureSpace(height + style.lineHeight + 6, orientation: orientation)
                let rect = CGRect(x: Self.margin, y: cursorY, width: contentWidth, height: height)
                currentPage.commands.append(.fill(rect, .tableHeaderFill))
                for (header, column) in zip(headers, columns) {
                    let lines = Self.wrap(header, width: column.width - 8, style: .tableHeader)
                    for (index, line) in lines.enumerated() {
                        let textRect = CGRect(
                            x: column.minX + 4,
                            y: cursorY + 4 + CGFloat(index) * TextStyle.tableHeader.lineHeight,
                            width: column.width - 8,
                            height: TextStyle.tableHeader.lineHeight,
                        )
                        currentPage.commands.append(.text(TextCommand(
                            text: line,
                            rect: textRect,
                            style: .tableHeader,
                            color: .white,
                            alignment: .left,
                        )))
                    }
                }
                cursorY += height
            }

            drawHeader()
            for row in rows {
                try Task.checkCancellation()
                let wrapped = zip(row, columns).map {
                    Self.wrap($0.0, width: $0.1.width - 8, style: style)
                }
                let lineCount = max(wrapped.map(\.count).max() ?? 1, 1)
                var lineOffset = 0
                while lineOffset < lineCount {
                    let availableHeight = contentBottom - cursorY - 8
                    let availableLines = Int(floor(availableHeight / style.lineHeight))
                    if availableLines < 1 {
                        startPage(orientation: orientation, continuedSection: currentSection)
                        drawHeader()
                        continue
                    }
                    let chunkCount = min(availableLines, lineCount - lineOffset)
                    let height = CGFloat(chunkCount) * style.lineHeight + 8
                    let rowRect = CGRect(
                        x: Self.margin,
                        y: cursorY,
                        width: contentWidth,
                        height: height,
                    )
                    if rowNumber.isMultiple(of: 2) {
                        currentPage.commands.append(.fill(rowRect, .alternateRow))
                    }
                    currentPage.commands.append(.stroke(rowRect, .tableRule))
                    for (lines, column) in zip(wrapped, columns) {
                        let sliceEnd = min(lineOffset + chunkCount, lines.count)
                        guard lineOffset < sliceEnd else { continue }
                        for (localIndex, line) in lines[lineOffset ..< sliceEnd].enumerated() {
                            let rect = CGRect(
                                x: column.minX + 4,
                                y: cursorY + 4 + CGFloat(localIndex) * style.lineHeight,
                                width: column.width - 8,
                                height: style.lineHeight,
                            )
                            currentPage.commands.append(.text(TextCommand(
                                text: line,
                                rect: rect,
                                style: style,
                                color: .primary,
                                alignment: .left,
                            )))
                        }
                    }
                    cursorY += height
                    lineOffset += chunkCount
                }
                rowNumber += 1
            }
            cursorY += 8
        }

        private static func wrap(_ text: String, width: CGFloat, style: TextStyle) -> [String] {
            let normalized = text.replacingOccurrences(of: "\t", with: " ")
            let paragraphs = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            var result: [String] = []
            for paragraph in paragraphs {
                let value = String(paragraph)
                if value.isEmpty {
                    result.append("")
                    continue
                }
                var line = ""
                for character in value {
                    let candidate = line + String(character)
                    if style.width(of: candidate) <= width || line.isEmpty {
                        line = candidate
                    } else {
                        let breakIndex = line.lastIndex(where: { $0.isWhitespace })
                        if let breakIndex {
                            let prefix = String(line[..<breakIndex])
                                .trimmingCharacters(in: .whitespaces)
                            if !prefix.isEmpty { result.append(prefix) }
                            let suffix = String(line[line.index(after: breakIndex)...])
                            line = suffix + String(character)
                        } else {
                            result.append(line)
                            line = String(character)
                        }
                    }
                }
                if !line.isEmpty { result.append(line) }
            }
            return result.isEmpty ? [""] : result
        }

        // MARK: Report sections

        private mutating func cover() throws {
            try Task.checkCancellation()
            startPage(orientation: .portrait)
            if document.isDemo {
                addLine(Copy.demoWarning, style: .demoTitle, color: .warning)
                cursorY += 18
            }
            addLine(Copy.reportTitle, style: .coverTitle, color: .accent)
            addLine(String(document.audit.report.year), style: .coverYear, color: .primary)
            cursorY += 32

            if let preparedFor = document.preparedFor {
                labelValue(Copy.preparedFor, preparedFor)
            }
            if let reference = document.reference {
                labelValue(Copy.reference, reference)
            }
            labelValue(
                Copy.generated,
                Self.timestamp(document.generatedAt, timeZone: document.audit.timeZone),
            )
            labelValue(Copy.reportID, document.reportID.uuidString)
            labelValue(Copy.reportingTimeZone, Self.timeZoneDescription(
                document.audit.timeZone,
                at: document.generatedAt,
            ))
            labelValue(Copy.appVersion, document.buildInfo.version ?? Copy.notAvailable)
            labelValue(Copy.appBuild, document.buildInfo.build ?? Copy.notAvailable)
            cursorY += 16
            paragraph(Copy.auditDisclaimer, style: .body, color: .secondary)
            if document.isDemo {
                paragraph(Copy.demoDisclaimer, style: .warningBody, color: .warning)
            }
        }

        private mutating func coverageSummary() throws {
            try Task.checkCancellation()
            beginSection(Copy.coverageSummary)
            let report = document.audit.report
            let present = Set(report.days.map(\.day))
            let cutoff = Self.coverageCutoff(
                reportYear: report.year,
                generatedAt: document.generatedAt,
                timeZone: document.audit.timeZone,
            )
            let missing = MissingDays.missingRanges(
                year: report.year,
                through: cutoff,
                present: present,
            )
            labelValue(Copy.distinctLoggedDays, String(report.days.count))
            labelValue(Copy.daysWithoutPresence, String(missing.reduce(0) { $0 + $1.dayCount }))
            labelValue(Copy.missingDateRanges, Self.missingRanges(missing))

            let sourceCounts = Dictionary(grouping: document.audit.samples, by: {
                $0.sample.source.discriminator
            }).mapValues(\.count)
            let sourceRows = [
                [Copy.gpsVisit, String(sourceCounts["gpsVisit", default: 0])],
                [
                    Copy.gpsSignificantChange,
                    String(sourceCounts["gpsSignificantChange", default: 0]),
                ],
                [Copy.manualCoordinate, String(sourceCounts["manual", default: 0])],
                [Copy.evidenceCoordinate, String(sourceCounts["evidenceImplied", default: 0])],
                [Copy.manualDayRecords, String(document.audit.manualDays.count)],
                [Copy.evidenceRecords, String(document.audit.evidence.count)],
            ]
            try table(
                headers: [Copy.source, Copy.count],
                widths: [0.78, 0.22],
                rows: sourceRows,
            )
            labelValue(
                Copy.trackedRegions,
                document.audit.trackedRegions.map(\.localizedName).joined(separator: ", "),
            )

            let calendar = Self.calendar(timeZone: document.audit.timeZone)
            let today = CalendarDay(from: document.generatedAt, in: calendar)
            if report.year == today.year, present.contains(today) {
                paragraph(Copy.todayIncomplete, style: .warningBody, color: .warning)
            }
        }

        private mutating func regionalTotals() throws {
            try Task.checkCancellation()
            beginSection(Copy.regionalTotals)
            paragraph(Copy.nonExclusiveExplanation)
            let rows = document.audit.report.totals
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key.localizedName < rhs.key.localizedName
                }
                .map { [$0.key.localizedName, String($0.value)] }
            try table(
                headers: [Copy.region, Copy.jurisdictionDays],
                widths: [0.76, 0.24],
                rows: rows.isEmpty ? [[Copy.none, "0"]] : rows,
            )
        }

        private mutating func dailyPresence() throws {
            try Task.checkCancellation()
            beginSection(Copy.dailyPresence)
            paragraph(Copy.dailyPresenceExplanation)
            let calendar = Self.calendar(timeZone: document.audit.timeZone)
            let rows = document.audit.report.days.map { day in
                let regions = Region.inCanonicalOrder(day.regions)
                    .map(\.localizedName)
                    .joined(separator: ", ")
                let bases = document.audit.bases(on: day.day, calendar: calendar)
                    .sorted(by: { Self.basisOrder($0) < Self.basisOrder($1) })
                    .map(Self.basisName)
                    .joined(separator: ", ")
                return [day.day.description, regions, bases]
            }
            try table(
                headers: [Copy.date, Copy.finalRegions, Copy.basis],
                widths: [0.20, 0.36, 0.44],
                rows: rows.isEmpty ? [[Copy.none, Copy.none, Copy.none]] : rows,
            )
        }

        private mutating func manualEntryAudit() throws {
            try Task.checkCancellation()
            beginSection(Copy.manualEntryAudit)
            paragraph(Copy.manualAuditExplanation)
            let rows = Self.groupedManualDays(document.audit.manualDays).map { group in
                [
                    Self.dayRange(group.firstDay, group.lastDay),
                    group.isAuthoritative ? Copy.authoritativeOverride : Copy.additiveBackfill,
                    group.regions.map(\.localizedName).joined(separator: ", "),
                    group.audit.map {
                        Self.timestamp($0.recordedAt, timeZone: document.audit.timeZone)
                    } ?? Copy.notAvailable,
                    group.audit.flatMap(\.note).flatMap(Self.nonempty) ?? Copy.none,
                    Self.auditLocation(group.audit, timeZone: document.audit.timeZone),
                ]
            }
            try table(
                headers: [
                    Copy.affectedDates,
                    Copy.mode,
                    Copy.regions,
                    Copy.recordedAt,
                    Copy.note,
                    Copy.editLocation,
                ],
                widths: [0.16, 0.14, 0.17, 0.18, 0.17, 0.18],
                rows: rows.isEmpty
                    ? [[Copy.none, Copy.none, Copy.none, Copy.none, Copy.none, Copy.none]]
                    : rows,
                style: .tableSmall,
            )
        }

        private mutating func evidenceIndex() throws {
            try Task.checkCancellation()
            beginSection(Copy.evidenceIndex)
            paragraph(Copy.evidenceExplanation)
            let rows = document.audit.evidence.map { evidence in
                [
                    evidence.id.uuidString,
                    Self.timestamp(evidence.capturedAt, timeZone: document.audit.timeZone),
                    WhereFormat.evidenceKind(evidence.kind),
                    evidence.region?.localizedName ?? Copy.notAssigned,
                    Self.contentType(evidence.contentType),
                    Self.nonempty(evidence.note ?? "") ?? Copy.none,
                ]
            }
            try table(
                headers: [
                    Copy.evidenceID,
                    Copy.captureDate,
                    Copy.kind,
                    Copy.assignedRegion,
                    Copy.contentType,
                    Copy.note,
                ],
                widths: [0.20, 0.17, 0.13, 0.16, 0.12, 0.22],
                rows: rows.isEmpty
                    ? [[Copy.none, Copy.none, Copy.none, Copy.none, Copy.none, Copy.none]]
                    : rows,
                style: .tableSmall,
            )
        }

        private mutating func methodology() throws {
            try Task.checkCancellation()
            beginSection(Copy.methodology)
            paragraph(Copy.methodCurrentDevice)
            paragraph(Copy.methodEditsImports)
            paragraph(Copy.methodTimezone)
            paragraph(Copy.methodManual)
            paragraph(Copy.methodOther)
            paragraph(Copy.methodNoCertification)

            if document.audit.regionDataSources.contains(where: { $0.fidelity == .approximate }) {
                paragraph(Copy.approximateGeometryWarning, style: .warningBody, color: .warning)
            }

            let sourceRows = document.audit.regionDataSources.map { source in
                let fidelity = source.fidelity == .authoritative
                    ? Copy.authoritativeGeometry
                    : Copy.approximateGeometry
                let regions = source.regions
                    .filter { document.audit.trackedRegions.contains($0) }
                    .map(\.localizedName)
                    .joined(separator: ", ")
                let links = [source.sourceURL, source.obtainedFromURL]
                    .compactMap { $0?.absoluteString }
                    .joined(separator: "\n")
                return [source.name, fidelity, regions, links.isEmpty ? Copy.notAvailable : links]
            }
            try table(
                headers: [Copy.geometrySource, Copy.fidelity, Copy.regions, Copy.sourceLinks],
                widths: [0.28, 0.16, 0.24, 0.32],
                rows: sourceRows,
                style: .tableSmall,
            )
        }

        private mutating func rawGPSAppendix() throws {
            try Task.checkCancellation()
            beginSection(Copy.rawGPSAppendix, orientation: .landscape)
            paragraph(
                Copy.rawGPSExplanation,
                style: .body,
                orientation: .landscape,
            )
            let rows = document.audit.samples
                .filter(\.sample.source.isGPS)
                .map { attributed in
                    let sample = attributed.sample
                    return [
                        sample.id.uuidString,
                        Self.timestamp(sample.timestamp, timeZone: document.audit.timeZone),
                        sample.source.discriminator,
                        attributed.region.localizedName,
                        String(
                            format: "%.6f",
                            locale: Locale(identifier: "en_US_POSIX"),
                            sample.coordinate.latitude,
                        ),
                        String(
                            format: "%.6f",
                            locale: Locale(identifier: "en_US_POSIX"),
                            sample.coordinate.longitude,
                        ),
                        String(
                            format: "%.0f %@",
                            locale: Locale(identifier: "en_US_POSIX"),
                            sample.horizontalAccuracy,
                            Copy.metersAbbreviation,
                        ),
                    ]
                }
            try table(
                headers: [
                    Copy.sampleUUID,
                    Copy.timestamp,
                    Copy.storedSource,
                    Copy.attributedRegion,
                    Copy.latitude,
                    Copy.longitude,
                    Copy.accuracy,
                ],
                widths: [0.25, 0.19, 0.13, 0.13, 0.10, 0.11, 0.09],
                rows: rows.isEmpty
                    ? [[
                        Copy.none,
                        Copy.none,
                        Copy.none,
                        Copy.none,
                        Copy.none,
                        Copy.none,
                        Copy.none,
                    ]]
                    : rows,
                orientation: .landscape,
                style: .tableTiny,
            )
        }

        // MARK: Formatting helpers

        private static func calendar(timeZone: TimeZone) -> Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar
        }

        private static func coverageCutoff(
            reportYear: Int,
            generatedAt: Date,
            timeZone: TimeZone,
        ) -> CalendarDay {
            let today = CalendarDay(from: generatedAt, in: calendar(timeZone: timeZone))
            if reportYear < today.year { return CalendarDay.lastDay(ofYear: reportYear) }
            if reportYear == today.year { return today.adding(days: -1) }
            return CalendarDay(year: reportYear, month: 1, day: 1).adding(days: -1)
        }

        private static func missingRanges(_ ranges: [MissingDayRange]) -> String {
            guard !ranges.isEmpty else { return Copy.none }
            return ranges.map { range in
                if range.start == range.end { return range.start.description }
                return "\(range.start.description) - \(range.end.description) (\(range.dayCount))"
            }.joined(separator: ", ")
        }

        private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = timeZone
            return formatter.string(from: date)
        }

        private static func timeZoneDescription(_ timeZone: TimeZone, at date: Date) -> String {
            let seconds = timeZone.secondsFromGMT(for: date)
            let sign = seconds < 0 ? "-" : "+"
            let absolute = abs(seconds)
            let hours = absolute / 3600
            let minutes = (absolute % 3600) / 60
            return "\(timeZone.identifier) (UTC\(sign)\(String(format: "%02d:%02d", hours, minutes)))"
        }

        private static func basisOrder(_ basis: YearAuditDayBasis) -> Int {
            switch basis {
                case .gps: 0
                case .manualCoordinate: 1
                case .evidenceDerivedCoordinate: 2
                case .additiveManualEntry: 3
                case .authoritativeManualOverride: 4
            }
        }

        private static func basisName(_ basis: YearAuditDayBasis) -> String {
            switch basis {
                case .gps: Copy.basisGPS
                case .manualCoordinate: Copy.basisManualCoordinate
                case .evidenceDerivedCoordinate: Copy.basisEvidenceCoordinate
                case .additiveManualEntry: Copy.basisAdditive
                case .authoritativeManualOverride: Copy.basisOverride
            }
        }

        private static func contentType(_ type: EvidenceContentType) -> String {
            switch type {
                case .pdf: Copy.typePDF
                case .image: Copy.typeImage
                case .plainText: Copy.typeText
                case .rawData: Copy.typeRawData
                case let .other(label): nonempty(label ?? "") ?? Copy.typeOther
            }
        }

        private static func auditLocation(
            _ audit: ManualEntryAudit?,
            timeZone: TimeZone,
        ) -> String {
            guard let location = audit?.location else { return Copy.notAvailable }
            return [
                timestamp(location.timestamp, timeZone: timeZone),
                String(
                    format: "%.6f, %.6f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    location.coordinate.latitude,
                    location.coordinate.longitude,
                ),
                String(
                    format: "%.0f %@",
                    locale: Locale(identifier: "en_US_POSIX"),
                    location.horizontalAccuracy,
                    Copy.metersAbbreviation,
                ),
            ].joined(separator: "\n")
        }

        private static func nonempty(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private static func groupedManualDays(_ days: [DayPresence]) -> [ManualGroup] {
            var groups: [ManualGroup] = []
            for day in days.sorted(by: { $0.day < $1.day }) {
                let regions = Region.inCanonicalOrder(day.regions)
                if let last = groups.last,
                   last.lastDay.adding(days: 1) == day.day,
                   last.isAuthoritative == day.isAuthoritative,
                   last.regions == regions,
                   last.audit == day.audit
                {
                    groups[groups.count - 1] = ManualGroup(
                        firstDay: last.firstDay,
                        lastDay: day.day,
                        regions: regions,
                        isAuthoritative: day.isAuthoritative,
                        audit: day.audit,
                    )
                } else {
                    groups.append(ManualGroup(
                        firstDay: day.day,
                        lastDay: day.day,
                        regions: regions,
                        isAuthoritative: day.isAuthoritative,
                        audit: day.audit,
                    ))
                }
            }
            return groups
        }

        private static func dayRange(_ first: CalendarDay, _ last: CalendarDay) -> String {
            first == last ? first.description : "\(first.description) - \(last.description)"
        }
    }

    fileprivate struct ManualGroup {
        let firstDay: CalendarDay
        let lastDay: CalendarDay
        let regions: [Region]
        let isAuthoritative: Bool
        let audit: ManualEntryAudit?
    }

    fileprivate enum Orientation {
        case portrait
        case landscape
    }

    fileprivate struct Page {
        let bounds: CGRect
        var commands: [DrawCommand]

        func draw(in context: CGContext) {
            for command in commands {
                switch command {
                    case let .fill(rect, color):
                        context.setFillColor(color.uiColor.cgColor)
                        context.fill(rect)
                    case let .stroke(rect, color):
                        context.setStrokeColor(color.uiColor.cgColor)
                        context.setLineWidth(0.35)
                        context.stroke(rect)
                    case let .text(command):
                        command.draw()
                }
            }
        }
    }

    fileprivate enum DrawCommand {
        case fill(CGRect, PDFColor)
        case stroke(CGRect, PDFColor)
        case text(TextCommand)
    }

    fileprivate struct TextCommand {
        let text: String
        let rect: CGRect
        let style: TextStyle
        let color: PDFColor
        let alignment: NSTextAlignment

        func draw() {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byClipping
            (text as NSString).draw(
                in: rect,
                withAttributes: [
                    .font: style.font,
                    .foregroundColor: color.uiColor,
                    .paragraphStyle: paragraph,
                ],
            )
        }
    }

    fileprivate enum TextStyle {
        case coverTitle
        case coverYear
        case demoTitle
        case sectionTitle
        case runningHeader
        case body
        case warningBody
        case label
        case tableHeader
        case table
        case tableSmall
        case tableTiny

        var font: UIFont {
            switch self {
                case .coverTitle: UIFont.systemFont(ofSize: 28, weight: .bold)
                case .coverYear: UIFont.systemFont(ofSize: 44, weight: .light)
                case .demoTitle: UIFont.systemFont(ofSize: 18, weight: .black)
                case .sectionTitle: UIFont.systemFont(ofSize: 20, weight: .bold)
                case .runningHeader: UIFont.systemFont(ofSize: 9, weight: .semibold)
                case .body: UIFont.systemFont(ofSize: 9.5)
                case .warningBody: UIFont.systemFont(ofSize: 9.5, weight: .semibold)
                case .label: UIFont.systemFont(ofSize: 9.5, weight: .semibold)
                case .tableHeader: UIFont.systemFont(ofSize: 7.5, weight: .bold)
                case .table: UIFont.systemFont(ofSize: 7.5)
                case .tableSmall: UIFont.systemFont(ofSize: 6.7)
                case .tableTiny: UIFont.monospacedSystemFont(ofSize: 6.2, weight: .regular)
            }
        }

        var lineHeight: CGFloat {
            ceil(font.lineHeight + 1)
        }

        func width(of text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    fileprivate enum PDFColor {
        case primary
        case secondary
        case accent
        case warning
        case white
        case tableHeaderFill
        case alternateRow
        case tableRule

        var uiColor: UIColor {
            switch self {
                case .primary: .black
                case .secondary: UIColor(white: 0.32, alpha: 1)
                case .accent: UIColor(red: 0.08, green: 0.27, blue: 0.48, alpha: 1)
                case .warning: UIColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1)
                case .white: .white
                case .tableHeaderFill: UIColor(red: 0.12, green: 0.28, blue: 0.45, alpha: 1)
                case .alternateRow: UIColor(white: 0.95, alpha: 1)
                case .tableRule: UIColor(white: 0.78, alpha: 1)
            }
        }
    }
}

extension YearPDFRenderer {
    fileprivate enum Copy {
        static var reportTitle: String {
            String(localized: .exportReportPdfTitle)
        }

        static var subject: String {
            String(localized: .exportReportPdfSubject)
        }

        static var filenamePrefix: String {
            String(localized: .exportReportFilename)
        }

        static var demoFilenamePrefix: String {
            String(localized: .exportReportDemoFilename)
        }

        static var demoWarning: String {
            String(localized: .exportReportDemoWarning)
        }

        static var demoDisclaimer: String {
            String(localized: .exportReportPdfDemoDisclaimer)
        }

        static var auditDisclaimer: String {
            String(localized: .exportReportPdfAuditDisclaimer)
        }

        static var preparedFor: String {
            String(localized: .exportReportPreparedFor)
        }

        static var reference: String {
            String(localized: .exportReportReference)
        }

        static var generated: String {
            String(localized: .exportReportPdfGenerated)
        }

        static var reportID: String {
            String(localized: .exportReportPdfReportId)
        }

        static var reportingTimeZone: String {
            String(localized: .exportReportPdfReportingTimeZone)
        }

        static var appVersion: String {
            String(localized: .exportReportPdfAppVersion)
        }

        static var appBuild: String {
            String(localized: .exportReportPdfAppBuild)
        }

        static var notAvailable: String {
            String(localized: .exportReportPdfNotAvailable)
        }

        static var none: String {
            String(localized: .exportReportPdfNone)
        }

        static var page: String {
            String(localized: .exportReportPdfPage)
        }

        static var of: String {
            String(localized: .exportReportPdfOf)
        }

        static var continued: String {
            String(localized: .exportReportPdfContinued)
        }

        static var coverageSummary: String {
            String(localized: .exportReportPdfCoverageSummary)
        }

        static var distinctLoggedDays: String {
            String(localized: .exportReportPdfDistinctLoggedDays)
        }

        static var daysWithoutPresence: String {
            String(localized: .exportReportPdfDaysWithoutPresence)
        }

        static var missingDateRanges: String {
            String(localized: .exportReportPdfMissingDateRanges)
        }

        static var source: String {
            String(localized: .exportReportPdfSource)
        }

        static var count: String {
            String(localized: .exportReportPdfCount)
        }

        static var gpsVisit: String {
            String(localized: .exportReportPdfGpsVisit)
        }

        static var gpsSignificantChange: String {
            String(localized: .exportReportPdfGpsSignificantChange)
        }

        static var manualCoordinate: String {
            String(localized: .exportReportPdfManualCoordinate)
        }

        static var evidenceCoordinate: String {
            String(localized: .exportReportPdfEvidenceCoordinate)
        }

        static var manualDayRecords: String {
            String(localized: .exportReportPdfManualDayRecords)
        }

        static var evidenceRecords: String {
            String(localized: .exportReportPdfEvidenceRecords)
        }

        static var trackedRegions: String {
            String(localized: .exportReportPdfTrackedRegions)
        }

        static var todayIncomplete: String {
            String(localized: .exportReportPdfTodayIncomplete)
        }

        static var regionalTotals: String {
            String(localized: .exportReportPdfRegionalTotals)
        }

        static var nonExclusiveExplanation: String {
            String(localized: .exportReportPdfNonExclusiveExplanation)
        }

        static var region: String {
            String(localized: .exportReportPdfRegion)
        }

        static var jurisdictionDays: String {
            String(localized: .exportReportPdfJurisdictionDays)
        }

        static var dailyPresence: String {
            String(localized: .exportReportPdfDailyPresence)
        }

        static var dailyPresenceExplanation: String {
            String(localized: .exportReportPdfDailyPresenceExplanation)
        }

        static var date: String {
            String(localized: .exportReportPdfDate)
        }

        static var finalRegions: String {
            String(localized: .exportReportPdfFinalRegions)
        }

        static var basis: String {
            String(localized: .exportReportPdfBasis)
        }

        static var basisGPS: String {
            String(localized: .exportReportPdfBasisGps)
        }

        static var basisManualCoordinate: String {
            String(localized: .exportReportPdfBasisManualCoordinate)
        }

        static var basisEvidenceCoordinate: String {
            String(localized: .exportReportPdfBasisEvidenceCoordinate)
        }

        static var basisAdditive: String {
            String(localized: .exportReportPdfBasisAdditive)
        }

        static var basisOverride: String {
            String(localized: .exportReportPdfBasisOverride)
        }

        static var manualEntryAudit: String {
            String(localized: .exportReportPdfManualEntryAudit)
        }

        static var manualAuditExplanation: String {
            String(localized: .exportReportPdfManualAuditExplanation)
        }

        static var affectedDates: String {
            String(localized: .exportReportPdfAffectedDates)
        }

        static var mode: String {
            String(localized: .exportReportPdfMode)
        }

        static var regions: String {
            String(localized: .exportReportPdfRegions)
        }

        static var recordedAt: String {
            String(localized: .exportReportPdfRecordedAt)
        }

        static var note: String {
            String(localized: .exportReportPdfNote)
        }

        static var editLocation: String {
            String(localized: .exportReportPdfEditLocation)
        }

        static var authoritativeOverride: String {
            String(localized: .exportReportPdfAuthoritativeOverride)
        }

        static var additiveBackfill: String {
            String(localized: .exportReportPdfAdditiveBackfill)
        }

        static var evidenceIndex: String {
            String(localized: .exportReportPdfEvidenceIndex)
        }

        static var evidenceExplanation: String {
            String(localized: .exportReportPdfEvidenceExplanation)
        }

        static var evidenceID: String {
            String(localized: .exportReportPdfEvidenceId)
        }

        static var captureDate: String {
            String(localized: .exportReportPdfCaptureDate)
        }

        static var kind: String {
            String(localized: .exportReportPdfKind)
        }

        static var assignedRegion: String {
            String(localized: .exportReportPdfAssignedRegion)
        }

        static var contentType: String {
            String(localized: .exportReportPdfContentType)
        }

        static var notAssigned: String {
            String(localized: .exportReportPdfNotAssigned)
        }

        static var typePDF: String {
            String(localized: .exportReportPdfTypePdf)
        }

        static var typeImage: String {
            String(localized: .exportReportPdfTypeImage)
        }

        static var typeText: String {
            String(localized: .exportReportPdfTypeText)
        }

        static var typeRawData: String {
            String(localized: .exportReportPdfTypeRawData)
        }

        static var typeOther: String {
            String(localized: .exportReportPdfTypeOther)
        }

        static var methodology: String {
            String(localized: .exportReportPdfMethodology)
        }

        static var methodCurrentDevice: String {
            String(localized: .exportReportPdfMethodCurrentDevice)
        }

        static var methodEditsImports: String {
            String(localized: .exportReportPdfMethodEditsImports)
        }

        static var methodTimezone: String {
            String(localized: .exportReportPdfMethodTimezone)
        }

        static var methodManual: String {
            String(localized: .exportReportPdfMethodManual)
        }

        static var methodOther: String {
            String(localized: .exportReportPdfMethodOther)
        }

        static var methodNoCertification: String {
            String(localized: .exportReportPdfMethodNoCertification)
        }

        static var approximateGeometryWarning: String {
            String(localized: .exportReportPdfApproximateGeometryWarning)
        }

        static var authoritativeGeometry: String {
            String(localized: .exportReportPdfAuthoritativeGeometry)
        }

        static var approximateGeometry: String {
            String(localized: .exportReportPdfApproximateGeometry)
        }

        static var geometrySource: String {
            String(localized: .exportReportPdfGeometrySource)
        }

        static var fidelity: String {
            String(localized: .exportReportPdfFidelity)
        }

        static var sourceLinks: String {
            String(localized: .exportReportPdfSourceLinks)
        }

        static var rawGPSAppendix: String {
            String(localized: .exportReportPdfRawGpsAppendix)
        }

        static var rawGPSExplanation: String {
            String(localized: .exportReportPdfRawGpsExplanation)
        }

        static var sampleUUID: String {
            String(localized: .exportReportPdfSampleUuid)
        }

        static var timestamp: String {
            String(localized: .exportReportPdfTimestamp)
        }

        static var storedSource: String {
            String(localized: .exportReportPdfStoredSource)
        }

        static var attributedRegion: String {
            String(localized: .exportReportPdfAttributedRegion)
        }

        static var latitude: String {
            String(localized: .exportReportPdfLatitude)
        }

        static var longitude: String {
            String(localized: .exportReportPdfLongitude)
        }

        static var accuracy: String {
            String(localized: .exportReportPdfAccuracy)
        }

        static var metersAbbreviation: String {
            String(localized: .exportReportPdfMetersAbbreviation)
        }
    }
}
