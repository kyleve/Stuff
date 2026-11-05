import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// The real report reader and controlled readers share this boundary. Eligibility and
/// content must be returned together; a consumer cannot substitute another report.
protocol HistoryReportExporting: Sendable {
    func exportableYearCSV(for year: Int) async throws -> HistoryReportCSV
}

extension ReportReader: HistoryReportExporting {}

/// One explicit export attempt. Review never automatically resumes an export, and a late
/// read or system callback cannot replace another attempt's state.
@MainActor
@Observable
final class HistoryReportExportModel {
    struct RequestID: Hashable { let value = UUID() }

    @MainActor
    @Observable
    final class Export {
        let id: RequestID
        let document: HistoryReportDocument
        var isPresented = true

        init(id: RequestID, document: HistoryReportDocument) {
            self.id = id
            self.document = document
        }
    }

    enum State {
        case idle
        case preparing(RequestID)
        case needsReview(HistoryCompleteness)
        case ready(Export)
        case saved
        case failed(any Error)

        var export: Export? {
            if case let .ready(export) = self { return export }
            return nil
        }
    }

    let year: Int
    let isAvailable: Bool
    private let source: any HistoryReportExporting
    private let validate: @Sendable () throws -> Void
    private var retired = false
    private(set) var state = State.idle {
        didSet {
            guard oldValue.export?.id != state.export?.id else { return }
            oldValue.export?.document.retire()
        }
    }

    var showingReview = false
    private static let logger = WhereLog.session(HistoryReportExportModelLog.self)

    init(
        source: any HistoryReportExporting,
        validate: @escaping @Sendable () throws -> Void,
        year: Int,
        isAvailable: Bool,
    ) {
        self.source = source
        self.validate = validate
        self.year = year
        self.isAvailable = isAvailable
    }

    isolated deinit { state.export?.document.retire() }

    var requestID: RequestID? {
        if case let .preparing(requestID) = state { return requestID }
        return nil
    }

    var canExport: Bool {
        guard !retired, isAvailable else { return false }
        switch state {
            case .preparing, .ready: return false
            case .idle, .needsReview, .saved, .failed: return true
        }
    }

    var isPresentingExporter: Bool {
        get { state.export?.isPresented ?? false }
        set { state.export?.isPresented = newValue }
    }

    func requestExport() {
        guard canExport else { return }
        state = .preparing(RequestID())
    }

    func prepare(_ requestID: RequestID) async {
        guard !retired, self.requestID == requestID else { return }
        do {
            try Task.checkCancellation()
            try validate()
            let report = try await source.exportableYearCSV(for: year)
            try Task.checkCancellation()
            try validate()
            guard !retired, self.requestID == requestID else { return }
            state = .ready(Export(
                id: requestID,
                document: HistoryReportDocument(report: report, validate: validate),
            ))
        } catch is CancellationError {
            if self.requestID == requestID { state = .idle }
        } catch {
            guard !retired, self.requestID == requestID else { return }
            do {
                try Task.checkCancellation()
                try validate()
                if let unresolved = error as? UnresolvedHistoryError {
                    state = .needsReview(unresolved.completeness)
                } else {
                    fail(error)
                }
            } catch is CancellationError {
                state = .idle
            } catch {
                fail(error)
            }
        }
    }

    func complete(_ result: Result<URL, any Error>, requestID: RequestID) {
        guard !retired, state.export?.id == requestID else { return }
        switch result {
            case .success: state = .saved
            case let .failure(error): fail(error)
        }
    }

    func cancelExport(_ requestID: RequestID) {
        guard state.export?.id == requestID else { return }
        state = .idle
    }

    /// A retained tab may return. Cancel only work that has not reached the system presenter.
    func cancelPreparation() {
        if case .preparing = state { state = .idle }
    }

    func deactivate() {
        retired = true
        state = .idle
        showingReview = false
    }

    private func fail(_ error: any Error) {
        state = .failed(error)
        Self.logger.operationFailed(error: .restricted(.errorDetails, error))
    }
}
