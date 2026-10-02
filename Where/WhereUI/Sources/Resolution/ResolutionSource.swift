import RegionKit
import WhereCore

/// The scene and standalone scanner publish through the same presentation seam.
@MainActor
protocol ResolutionSource {
    var resolutionState: ResolutionSourceState { get }
    func refreshResolution(year: Int, primaryRegions: [Region]) async
}

enum ResolutionSourceState {
    case idle
    case loaded(DataIssueScanResult)
    case failed(String, previous: DataIssueScanResult?)
}

extension YearReportModel: ResolutionSource {
    var resolutionState: ResolutionSourceState {
        if let dataIssueScanError { return .failed(dataIssueScanError, previous: dataIssueScan) }
        if let dataIssueScan { return .loaded(dataIssueScan) }
        return .idle
    }

    func refreshResolution(year _: Int, primaryRegions _: [Region]) async {
        if dataIssueScan == nil, dataIssueScanError == nil {
            await refreshDataIssueCount(force: false)
        }
    }
}
