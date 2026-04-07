import Foundation

public struct ManualImportPreview: Equatable, Sendable {
    public let yearSpan: ClosedRange<Int>?
    public let entryCount: Int
    public let evidenceAttachmentCount: Int
    public let sharedEvidenceAttachmentCount: Int
    public let entries: [ManualImportEntryDraft]
    public let issues: [Issue]

    public init(
        yearSpan: ClosedRange<Int>?,
        entryCount: Int,
        evidenceAttachmentCount: Int,
        sharedEvidenceAttachmentCount: Int,
        entries: [ManualImportEntryDraft],
        issues: [Issue] = [],
    ) {
        self.yearSpan = yearSpan
        self.entryCount = entryCount
        self.evidenceAttachmentCount = evidenceAttachmentCount
        self.sharedEvidenceAttachmentCount = sharedEvidenceAttachmentCount
        self.entries = entries
        self.issues = issues
    }

    public var isValid: Bool {
        !entries.isEmpty && !issues.contains(where: { $0.severity == .error })
    }

    public var hasWarnings: Bool {
        issues.contains(where: { $0.severity == .warning })
    }

    public struct Issue: Equatable, Sendable, Identifiable {
        public enum Severity: String, Equatable, Sendable {
            case error
            case warning
        }

        public let id: UUID
        public let severity: Severity
        public let message: String

        public init(
            id: UUID = UUID(),
            severity: Severity,
            message: String,
        ) {
            self.id = id
            self.severity = severity
            self.message = message
        }
    }
}
