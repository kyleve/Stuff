import Foundation
import PeriscopeCore
import WhereCore

/// Loads all-history work for consumers that do not share a scene's YearReportModel.
@MainActor
final class ScannerResolutionSource: ResolutionSource {
    private(set) var resolutionState = ResolutionSourceState.idle
    private var requestID = UUID()
    private let services: WhereServices
    private let preferences: WherePreferences
    private static let logger = WhereLog.session(ResolveModelLog.self)

    init(services: WhereServices, preferences: WherePreferences) {
        self.services = services
        self.preferences = preferences
    }

    func refreshResolution() async {
        let request = UUID()
        requestID = request
        do {
            let scan = try await services.resolution.historicalScan(
                driftThresholdMeters: Double(preferences.driftThresholdMeters),
                force: false,
            )
            guard request == requestID, !Task.isCancelled else { return }
            try services.validateDataAccess()
            resolutionState = .loaded(scan)
        } catch is CancellationError {
            return
        } catch {
            guard request == requestID, !Task.isCancelled else { return }
            resolutionState = .failed(
                error,
                previous: services.isDataAccessRevoked ? nil : resolutionState.scan,
            )
            Self.logger.dataIssueScanFailed(error: .restricted(.errorDetails, error))
        }
    }
}
