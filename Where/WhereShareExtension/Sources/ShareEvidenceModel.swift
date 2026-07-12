import Foundation
import LogKit
import Observation
import UniformTypeIdentifiers
import WhereCore

/// View-scoped model for the share-extension compose sheet. Pulls the shared
/// bytes out of the extension items, holds the editable fields (kind, capture
/// date, note), and persists a new `Evidence` straight into the App Group
/// SwiftData store the app reads.
///
/// The extension writes to the store directly rather than through
/// `WhereServices`/`DayJournal`: those assemble a live GPS ingestor, notifiers,
/// and widget publishing that have no place in a short-lived share process. The
/// store commit pings persistent history, so the app reconciles badges/widgets
/// and (in production) mirrors to CloudKit the next time it opens.
@MainActor
@Observable
final class ShareEvidenceModel {
    /// Where the compose sheet is in its lifecycle. Success isn't a case — the
    /// host view controller dismisses on the `true` return from `save()`.
    enum Phase: Equatable {
        /// Extracting the shared attachment before the form is shown.
        case loading
        /// Form is editable.
        case composing
        case saving
        /// A save failed; the form stays open with the message visible.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var attachment: SharedAttachment?

    /// Editable form fields (bound directly by the view).
    var kind: EvidenceKind = .document
    /// Free-text label used only when `kind` is `.other`.
    var otherLabel: String = ""
    var capturedAt: Date
    var note: String = ""

    private let items: [NSExtensionItem]
    private let now: @Sendable () -> Date
    /// Storage the extension opens; injectable so a future test can point it at
    /// an in-memory store instead of the shared container.
    private let storage: SwiftDataStore.Storage
    private static let logger = WhereLog.channel(.shareExtension)

    init(
        items: [NSExtensionItem],
        storage: SwiftDataStore.Storage = .localOnly,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.items = items
        self.storage = storage
        self.now = now
        capturedAt = now()
    }

    var isSaving: Bool {
        phase == .saving
    }

    /// The save error message, if the last save failed. Backing for the alert
    /// binding below.
    var saveErrorMessage: String? {
        if case let .failed(message) = phase { return message }
        return nil
    }

    /// Derived binding for the save-failure alert: reading maps the `.failed`
    /// phase to a `Bool`; dismissing returns to `.composing`. Keeps `phase` the
    /// single source of truth (no closure-based `Binding`).
    var isShowingSaveError: Bool {
        get { saveErrorMessage != nil }
        set { if !newValue { phase = .composing } }
    }

    /// Pull the first usable attachment out of the shared items and open the
    /// form. A share with nothing loadable still composes — the user can save
    /// metadata only.
    func loadAttachment() async {
        let loaded = await SharedItemLoader.loadFirstAttachment(from: items)
        attachment = loaded
        if let loaded {
            kind = Self.defaultKind(for: loaded)
        }
        phase = .composing
    }

    /// Build the `Evidence` from the form and persist it (with any attachment
    /// bytes). Returns `true` on success so the host can dismiss; on failure
    /// records `.failed(_)`, logs, and returns `false` so the form stays open.
    /// Never silently swallows the write error.
    func save() async -> Bool {
        phase = .saving
        let evidence = buildEvidence()
        let blob = attachment?.data
        do {
            let store = try SwiftDataStore.make(storage: storage)
            try await store.perform { try await store.write(evidence: evidence, blob: blob) }
            Self.logger.info("Saved shared evidence \(evidence.id) (blob: \(blob != nil))")
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            Self.logger.error("Failed to save shared evidence: \(error.localizedDescription)")
            return false
        }
    }

    /// Assemble the `Evidence` value from the current field state. `internal`
    /// so a test can assert the mapping without going through persistence.
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

    /// A reasonable starting kind from the attachment's declared type, so the
    /// user usually doesn't have to change the picker (a photo defaults to
    /// `.photo`, a Wallet pass to `.boardingPass`, everything else `.document`).
    private static func defaultKind(for attachment: SharedAttachment) -> EvidenceKind {
        guard let identifier = attachment.typeIdentifier,
              let type = UTType(identifier)
        else { return .document }
        if type.identifier == "com.apple.pkpass" { return .boardingPass }
        if type.conforms(to: .image) { return .photo }
        return .document
    }
}
