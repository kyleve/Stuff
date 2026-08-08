import Foundation
import WhereCore

/// Immutable inputs for one PDF generation pass. The report already carries a
/// captured attribution policy and time zone; identity fields remain only in
/// this ephemeral value and are never persisted or logged.
struct YearPDFDocument {
    let audit: YearAuditReport
    let generatedAt: Date
    let reportID: UUID
    let preparedFor: String?
    let reference: String?
    let pageSize: YearPDFPageSize
    let includeRawGPS: Bool
    let isDemo: Bool
    let buildInfo: BuildInfo
}
