import Foundation
import LogKit
import Observation
import WhereCore

/// View-scoped model for a single evidence record's detail: loads the
/// attachment bytes (which live separately from the metadata) into a state the
/// preview renders. Distinguishes "still loading", "loaded with no attachment",
/// and "load failed" so the detail view never mistakes a read error for an
/// attachment-less record.
@MainActor
@Observable
public final class EvidenceDetailModel {
    /// Where the attachment bytes are in their load lifecycle.
    public enum BlobState: Equatable {
        case idle
        case loading
        /// Loaded; `nil` means the record has no stored attachment.
        case loaded(Data?)
        case failed(String)
    }

    public let evidence: Evidence
    public private(set) var blobState: BlobState = .idle

    private let services: WhereServices
    private static let logger = WhereLog.channel(.evidence)

    init(evidence: Evidence, services: WhereServices) {
        self.evidence = evidence
        self.services = services
    }

    /// Fetch the attachment bytes for this record. A missing attachment loads as
    /// `.loaded(nil)`; a read failure surfaces as `.failed(_)` + a warning.
    public func load() async {
        blobState = .loading
        do {
            let blob = try await services.evidence.blob(for: evidence.id)
            blobState = .loaded(blob)
        } catch {
            blobState = .failed(error.localizedDescription)
            Self.logger.warning(
                "Failed to load evidence blob for \(evidence.id): \(error.localizedDescription)",
            )
        }
    }

    #if DEBUG
        /// Force a state for previews/tests without touching the store.
        func previewLoad(_ state: BlobState) {
            blobState = state
        }
    #endif
}
