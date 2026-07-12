import Foundation
import LogKit
import Observation
import WhereCore

/// Bytes the user picked to attach to a new piece of evidence, plus the hints
/// needed to classify and label them. A small named value (not a tuple) since
/// it escapes the picker callback into the model's state.
public struct PickedAttachment: Equatable, Sendable {
    public let data: Data
    /// Uniform type identifier from the picker (file `contentType`, photo item
    /// `supportedContentTypes`), if known — authoritative input to
    /// `EvidenceContentType.classify`.
    public let typeIdentifier: String?
    /// Original file name, for display in the form. Photos have none.
    public let filename: String?

    public init(data: Data, typeIdentifier: String?, filename: String?) {
        self.data = data
        self.typeIdentifier = typeIdentifier
        self.filename = filename
    }
}

/// View-scoped model for the in-app "add evidence" compose form. Holds the
/// editable fields (kind, capture date, note, optional attachment), builds an
/// `Evidence` value from them, and persists it through `DayJournal`. Save
/// failures surface honestly (state + log) so the form can stay open.
@MainActor
@Observable
public final class AddEvidenceModel {
    /// Where a save is in its lifecycle. Success isn't a case — the view
    /// dismisses on the `true` return from `save()`.
    public enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)
    }

    /// Editable form fields (bound directly by the view).
    public var kind: EvidenceKind = .document
    /// Free-text label used only when `kind` is `.other`.
    public var otherLabel: String = ""
    public var capturedAt: Date
    public var note: String = ""

    public private(set) var attachment: PickedAttachment?
    public private(set) var saveState: SaveState = .idle
    /// Set when picking/reading an attachment fails; drives an alert.
    public private(set) var attachmentError: String?

    private let services: WhereServices
    private static let logger = WhereLog.channel(.evidence)

    init(services: WhereServices, now: @Sendable () -> Date = { Date() }) {
        self.services = services
        capturedAt = now()
    }

    public var isSaving: Bool {
        saveState == .saving
    }

    /// The save error message, if the last save failed. Backing for the alert
    /// binding below.
    public var saveErrorMessage: String? {
        if case let .failed(message) = saveState { return message }
        return nil
    }

    /// Derived binding for the save-failure alert: reading maps the `.failed`
    /// state to a `Bool`; dismissing resets to `.idle`. Keeps `saveState` the
    /// single source of truth (no closure-based `Binding`).
    public var isShowingSaveError: Bool {
        get { saveErrorMessage != nil }
        set { if !newValue { saveState = .idle } }
    }

    /// Derived binding for the attachment-failure alert (see
    /// `isShowingSaveError`).
    public var isShowingAttachmentError: Bool {
        get { attachmentError != nil }
        set { if !newValue { attachmentError = nil } }
    }

    public func setAttachment(_ attachment: PickedAttachment) {
        self.attachment = attachment
    }

    public func removeAttachment() {
        attachment = nil
    }

    public func reportAttachmentError(_ message: String) {
        attachmentError = message
        Self.logger.warning("Evidence attachment pick failed: \(message)")
    }

    /// Build the `Evidence` from the form and persist it (with any attachment
    /// bytes). Returns `true` on success so the view can dismiss; on failure
    /// records `.failed(_)`, logs, and returns `false` so the form stays open
    /// with the error visible. Never silently swallows the write error.
    public func save() async -> Bool {
        saveState = .saving
        let evidence = buildEvidence()
        do {
            try await services.journal.addEvidence(evidence, blob: attachment?.data)
            Self.logger.info("Saved evidence \(evidence.id) from compose form")
            return true
        } catch {
            saveState = .failed(error.localizedDescription)
            Self.logger.warning("Failed to save evidence: \(error.localizedDescription)")
            return false
        }
    }

    /// Assemble the `Evidence` value from the current field state. `internal`
    /// so tests can assert the mapping without going through persistence.
    func buildEvidence() -> Evidence {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType: EvidenceContentType = attachment
            .map { EvidenceContentType.classify(data: $0.data, typeIdentifier: $0.typeIdentifier) }
            ?? .other(nil)
        return Evidence(
            kind: resolvedKind(),
            capturedAt: capturedAt,
            region: nil,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            contentType: contentType,
        )
    }

    /// Fold the free-text `otherLabel` into the kind when `.other` is selected;
    /// every other kind carries no label.
    private func resolvedKind() -> EvidenceKind {
        guard case .other = kind else { return kind }
        let trimmed = otherLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return .other(trimmed.isEmpty ? nil : trimmed)
    }
}
