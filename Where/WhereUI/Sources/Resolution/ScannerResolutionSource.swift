import Foundation
import PeriscopeCore
import RegionKit
import WhereCore

/// Loads a scan for consumers that do not share a scene's YearReportModel.
@MainActor
final class ScannerResolutionSource: ResolutionSource {
    private(set) var resolutionState = ResolutionSourceState.idle
    private var requestID = UUID()
    private let scanner: DataIssueScanner
    private let preferences: WherePreferences
    private static let logger = WhereLog.session(ResolveModelLog.self)

    init(scanner: DataIssueScanner, preferences: WherePreferences) {
        self.scanner = scanner
        self.preferences = preferences
    }

    func refreshResolution(year: Int, primaryRegions: [Region]) async {
        let request = UUID()
        requestID = request
        do {
            let scan = try await scanner.scan(
                year: year,
                primaryRegions: primaryRegions,
                driftThresholdMeters: Double(preferences.driftThresholdMeters),
                force: false,
            )
            guard request == requestID, !Task.isCancelled else { return }
            resolutionState = .loaded(scan)
        } catch is CancellationError {
            return
        } catch {
            guard request == requestID, !Task.isCancelled else { return }
            let previous: DataIssueScanResult? = switch resolutionState {
                case .idle: nil
                case let .loaded(scan): scan
                case let .failed(_, previous): previous
            }
            resolutionState = .failed(error.localizedDescription, previous: previous)
            Self.logger.dataIssueScanFailed(description: .restricted(.errorDetails, error.localizedDescription))
        }
    }
}
