import Foundation
import Observation

/// Presents the result of an explicit historical scan without treating a retained stale count
/// as a successful refresh. The scene remains the owner of the shared assessment.
@MainActor
@Observable
final class IssueSearchModel {
    enum State {
        case idle
        case scanning
        case complete(Int)
        case failed(any Error)
    }

    private struct RequestID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private let report: YearReportModel
    private(set) var state = State.idle

    init(report: YearReportModel) {
        self.report = report
    }

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    func scan() async {
        guard !isScanning else { return }
        let request = RequestID()
        requestID = request
        let previous = report.resolutionState.scan?.revision
        state = .scanning
        await report.rescanForIssues()
        guard requestID == request else { return }
        guard !Task.isCancelled else {
            state = .idle
            return
        }
        do {
            try report.services.validateDataAccess()
            if let error = report.resolutionState.error { throw error }
            guard let current = report.resolutionState.scan, current.revision != previous else {
                state = .idle
                return
            }
            state = .complete(report.dataIssueCount)
        } catch {
            state = .failed(error)
        }
    }

    func invalidate() {
        requestID = RequestID()
        state = .idle
    }
}
