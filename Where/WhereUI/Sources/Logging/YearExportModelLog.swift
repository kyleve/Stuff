import PeriscopeCore

/// Privacy-minimized annual-export events. Identity fields, notes, coordinates,
/// raw rows, filenames, and file paths never enter this scope.
enum YearExportModelLog: LogEvent {
    enum SpanName: Hashable {
        case generation
    }

    case generated(
        year: Int,
        dayCount: Int,
        manualCount: Int,
        evidenceCount: Int,
        gpsCount: Int,
        includedGPS: Bool,
        pageCount: Int,
    )
    case failed(year: Int, failureType: String)
    case cleanupFailed(failureType: String)

    static let eventName = "YearExport"

    var level: LogLevel {
        switch self {
            case .generated: .info
            case .failed, .cleanupFailed: .warning
        }
    }

    var message: String {
        switch self {
            case let .generated(
            year,
            dayCount,
            manualCount,
            evidenceCount,
            gpsCount,
            includedGPS,
            pageCount,
        ):
                "Generated annual report for \(year) (\(dayCount) days, \(manualCount) manual, \(evidenceCount) evidence, \(gpsCount) GPS, raw GPS: \(includedGPS), \(pageCount) pages)"
            case let .failed(year, failureType):
                "Annual report generation failed for \(year) (\(failureType))"
            case let .cleanupFailed(failureType):
                "Annual report cleanup failed (\(failureType))"
        }
    }
}
