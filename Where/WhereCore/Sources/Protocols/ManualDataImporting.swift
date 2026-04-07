import Foundation

public protocol ManualDataImporting: Sendable {
    func previewBackfill(_ request: ManualImportBackfillRequest) async -> ManualImportPreview
    func previewPackage(at directoryURL: URL) async -> ManualImportPreview
    func importEntries(_ entries: [ManualImportEntryDraft]) async -> [ManualEntryRecord]
    func importPackage(at directoryURL: URL) async -> [ManualEntryRecord]
}
