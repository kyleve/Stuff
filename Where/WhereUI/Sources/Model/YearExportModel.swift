import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Sheet-scoped annual-export state. Form values live only here, generation is
/// one explicit state machine, and finished files have a bounded lifetime.
@MainActor
@Observable
final class YearExportModel {
    enum GenerationState: Equatable {
        case idle
        case generating(completedPages: Int, totalPages: Int?)
        case ready(YearPDFFile)
        case failed
    }

    private(set) var state: GenerationState = .idle

    var selectedYear: Int {
        didSet {
            guard oldValue != selectedYear else { return }
            invalidateReadyFile()
        }
    }

    var preparedFor = "" {
        didSet {
            guard oldValue != preparedFor else { return }
            invalidateReadyFile()
        }
    }

    var reference = "" {
        didSet {
            guard oldValue != reference else { return }
            invalidateReadyFile()
        }
    }

    var pageSize: YearPDFPageSize {
        didSet {
            guard oldValue != pageSize else { return }
            invalidateReadyFile()
        }
    }

    var includeRawGPS = false {
        didSet {
            guard oldValue != includeRawGPS else { return }
            invalidateReadyFile()
        }
    }

    let availableYears: [Int]

    private let reader: ReportReader
    private let now: @Sendable () -> Date
    private let buildInfo: BuildInfo
    private let renderer: any YearPDFRendering
    private let retention: Duration
    private let cleanup: @Sendable (URL) throws -> Void

    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    private static let logger = WhereLog.session(YearExportModelLog.self)

    init(
        reader: ReportReader,
        displayedYear: Int,
        calendar: Calendar,
        locale: Locale,
        buildInfo: BuildInfo,
        now: @escaping @Sendable () -> Date,
        renderer: any YearPDFRendering = YearPDFRenderer(),
        retention: Duration = .seconds(600),
        cleanup: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        },
    ) {
        self.reader = reader
        self.now = now
        self.buildInfo = buildInfo
        self.renderer = renderer
        self.retention = retention
        self.cleanup = cleanup
        let referenceDate = now()
        selectedYear = YearExportDefaults.selectedYear(
            displayedYear: displayedYear,
            now: referenceDate,
            calendar: calendar,
        )
        availableYears = YearExportDefaults.availableYears(
            displayedYear: displayedYear,
            now: referenceDate,
            calendar: calendar,
        )
        pageSize = YearPDFPageSize.defaultValue(for: locale)
    }

    var progressFraction: Double? {
        guard case let .generating(completed, total?) = state, total > 0 else { return nil }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    var isShowingFailure: Bool {
        get { state == .failed }
        set {
            if !newValue, state == .failed { state = .idle }
        }
    }

    /// Build and render one immutable report. Cancellation returns to `idle`,
    /// while a recoverable failure becomes an honest retryable state.
    func generate(isDemo: Bool) async -> YearPDFFile? {
        guard !isGenerating else { return nil }
        cleanupTask?.cancel()
        cleanupTask = nil
        invalidateReadyFile()

        let year = selectedYear
        let preparedFor = Self.nonempty(preparedFor)
        let reference = Self.nonempty(reference)
        let pageSize = pageSize
        let includeRawGPS = includeRawGPS
        state = .generating(completedPages: 0, totalPages: nil)
        let (updates, continuation) = AsyncStream<YearPDFProgress>.makeStream()
        let observer = Task { @MainActor [weak self] in
            for await update in updates {
                guard let self else { return }
                state = .generating(
                    completedPages: update.completedPages,
                    totalPages: update.totalPages,
                )
            }
        }
        defer { observer.cancel() }

        do {
            let generatedAt = now()
            let audit = try await reader.auditReport(for: year)
            try Task.checkCancellation()
            let document = YearPDFDocument(
                audit: audit,
                generatedAt: generatedAt,
                reportID: UUID(),
                preparedFor: preparedFor,
                reference: reference,
                pageSize: pageSize,
                includeRawGPS: includeRawGPS,
                isDemo: isDemo,
                buildInfo: buildInfo,
            )
            let file = try await Self.logger.measure(.generation, budget: .seconds(10)) {
                try await renderer.render(document: document) {
                    continuation.yield($0)
                }
            }
            if Task.isCancelled {
                do {
                    try cleanup(file.storageDirectory)
                } catch {
                    Self.logger {
                        .cleanupFailed(failureType: String(reflecting: type(of: error)))
                    }
                }
                throw CancellationError()
            }
            continuation.finish()
            await observer.value
            state = .ready(file)

            let gpsCount = audit.samples.count { $0.sample.source.isGPS }
            Self.logger {
                .generated(
                    year: year,
                    dayCount: audit.report.days.count,
                    manualCount: audit.manualDays.count,
                    evidenceCount: audit.evidence.count,
                    gpsCount: gpsCount,
                    includedGPS: document.includeRawGPS,
                    pageCount: file.pageCount,
                )
            }
            return file
        } catch is CancellationError {
            continuation.finish()
            state = .idle
            return nil
        } catch {
            continuation.finish()
            state = .failed
            Self.logger {
                .failed(year: year, failureType: String(reflecting: type(of: error)))
            }
            return nil
        }
    }

    var isGenerating: Bool {
        if case .generating = state { true } else { false }
    }

    /// A retry is just another generation pass; the caller uses this to return
    /// the error presentation to an editable state first.
    func acknowledgeFailure() {
        guard state == .failed else { return }
        state = .idle
    }

    /// Keep a successfully shared file available briefly after the sheet goes
    /// away, giving an in-progress share destination time to copy it.
    func sheetDidDismiss() {
        guard case let .ready(file) = state else { return }
        cleanupTask?.cancel()
        let retention = retention
        let cleanup = cleanup
        cleanupTask = Task { [weak self] in
            do {
                try await Task.sleep(for: retention)
                try Task.checkCancellation()
                try cleanup(file.storageDirectory)
                guard let self else { return }
                if state == .ready(file) {
                    state = .idle
                }
            } catch is CancellationError {
                return
            } catch {
                Self.logger {
                    .cleanupFailed(failureType: String(reflecting: type(of: error)))
                }
            }
        }
    }

    /// Used whenever form input changes or a replacement generation starts.
    /// Superseded output is no longer shareable, so remove it immediately.
    private func invalidateReadyFile() {
        guard case let .ready(file) = state else { return }
        cleanupTask?.cancel()
        cleanupTask = nil
        do {
            try cleanup(file.storageDirectory)
        } catch {
            Self.logger {
                .cleanupFailed(failureType: String(reflecting: type(of: error)))
            }
        }
        state = .idle
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
