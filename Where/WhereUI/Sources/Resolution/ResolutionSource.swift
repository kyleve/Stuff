import WhereCore

/// The scene and standalone scanner publish the same complete historical assessment.
@MainActor
protocol ResolutionSource {
    var resolutionState: ResolutionSourceState { get }
    func refreshResolution() async
}

enum ResolutionSourceState {
    case idle
    case loaded(HistoricalDataIssueScanResult)
    case failed(any Error, previous: HistoricalDataIssueScanResult?)

    var scan: HistoricalDataIssueScanResult? {
        switch self {
            case .idle: nil
            case let .loaded(scan): scan
            case let .failed(_, previous): previous
        }
    }

    var error: (any Error)? {
        switch self {
            case .idle, .loaded: nil
            case let .failed(error, _): error
        }
    }
}

extension YearReportModel: ResolutionSource {
    func refreshResolution() async {
        if case .idle = resolutionState {
            await refreshDataIssueCount(force: false)
        }
    }
}
