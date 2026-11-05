import CoreTransferable
import Foundation
import Synchronization
import UniformTypeIdentifiers
import WhereCore

/// The system exporter receives only an assessed CSV. Recheck its admitted lifetime when
/// the system requests bytes, and reject requests after this export session ends.
struct HistoryReportDocument: Transferable {
    enum ExportError: Error { case retired }

    private final class Lifetime: Sendable {
        let active = Mutex(true)
    }

    private let report: HistoryReportCSV
    private let validate: @Sendable () throws -> Void
    private let lifetime = Lifetime()

    init(report: HistoryReportCSV, validate: @escaping @Sendable () throws -> Void) {
        self.report = report
        self.validate = validate
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            try document.exportedData()
        }
    }

    func exportedData() throws -> Data {
        try lifetime.active.withLock { active in
            guard active else { throw ExportError.retired }
            try Task.checkCancellation()
            try validate()
            return report.data
        }
    }

    func retire() {
        lifetime.active.withLock { $0 = false }
    }
}
