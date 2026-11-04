import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Composes an immutable pending share with attachment bytes. Only an admitted app session
/// imports it into history; this extension never opens SwiftData or CloudKit.
@MainActor
@Observable
final class ShareEvidenceModel {
    /// Where the compose sheet is in its lifecycle. Success isn't a case — the
    /// host view controller dismisses on the `true` return from `save()`.
    enum Phase {
        /// Extracting the shared attachment before the form is shown.
        case loading
        /// Form is editable.
        case composing
        case saving
        /// A save failed; the form stays open with the message visible.
        case failed(any Error)
    }

    private(set) var phase: Phase = .loading
    private(set) var attachments: [SharedAttachment] = []

    /// Editable form fields (bound directly by the view).
    var kind: EvidenceKind = .document
    /// Free-text label used only when `kind` is `.other`.
    var otherLabel: String = ""
    var capturedAt: Date
    var note: String = ""

    private let items: [NSExtensionItem]
    private let makeQueue: @Sendable () throws -> any SharedEvidenceDraftQueuing
    private var preparedDraft: SharedEvidenceDraft?
    private static let logger = WhereLog.root(ShareExtensionLog.self)

    init(
        items: [NSExtensionItem],
        makeQueue: @escaping @Sendable () throws -> any SharedEvidenceDraftQueuing,
        now: @Sendable () -> Date = { Date() },
    ) {
        self.items = items
        self.makeQueue = makeQueue
        capturedAt = now()
    }

    var isSaving: Bool {
        if case .saving = phase { true } else { false }
    }

    var isLoading: Bool {
        if case .loading = phase { true } else { false }
    }

    /// An uncertain enqueue retries exactly the same identity and bytes.
    var hasPreparedDraft: Bool {
        preparedDraft != nil
    }

    /// The save error message, if the last save failed. Backing for the alert
    /// binding below.
    var saveErrorMessage: String? {
        if case let .failed(error) = phase { return error.localizedDescription }
        return nil
    }

    /// Derived binding for the save-failure alert: reading maps the `.failed`
    /// phase to a `Bool`; dismissing returns to `.composing`. Keeps `phase` the
    /// single source of truth (no closure-based `Binding`).
    var isShowingSaveError: Bool {
        get { saveErrorMessage != nil }
        set { if !newValue { phase = .composing } }
    }

    /// Pull every usable attachment out of the shared items and open the form.
    /// A share with nothing loadable still composes — the user can save metadata
    /// only.
    func loadAttachments() async {
        guard isLoading else { return }
        let loaded = await SharedItemLoader.loadAttachments(from: items)
        guard isLoading, preparedDraft == nil else { return }
        attachments = loaded
        if let first = attachments.first {
            kind = EvidenceKind.suggested(forTypeIdentifier: first.typeIdentifier)
        }
        phase = .composing
    }

    /// Save the complete batch atomically before the host dismisses. Retain the prepared
    /// identity through a failed or uncertain enqueue so another Save cannot duplicate it.
    func save() async -> Bool {
        guard !isSaving, !isLoading else { return false }
        phase = .saving
        do {
            let draft: SharedEvidenceDraft
            if let preparedDraft {
                draft = preparedDraft
            } else {
                draft = try SharedEvidenceDraft(
                    id: .init(rawValue: UUID()),
                    items: buildPendingEvidence(),
                )
                preparedDraft = draft
            }
            try await makeQueue().enqueue(draft)
            Self.logger.saved(evidenceCount: .restricted(.count, draft.items.count))
            return true
        } catch {
            phase = .failed(error)
            Self.logger.saveFailed(error: .restricted(.errorDetails, error))
            return false
        }
    }

    /// Assemble the evidence records from the current field state via the shared
    /// `Evidence.composed` factory: one per attachment (each classified from its
    /// own bytes), or a single metadata-only record when nothing was shared.
    /// `internal` so a test can assert the mapping without going through
    /// persistence.
    func buildPendingEvidence() -> [SharedEvidenceDraft.Item] {
        guard !attachments.isEmpty else {
            return [SharedEvidenceDraft.Item(evidence: composed(attachment: nil), blob: nil)]
        }
        return attachments.map { attachment in
            SharedEvidenceDraft.Item(
                evidence: composed(attachment: attachment),
                blob: attachment.data,
            )
        }
    }

    private func composed(attachment: SharedAttachment?) -> Evidence {
        Evidence.composed(
            kind: kind,
            otherLabel: otherLabel,
            capturedAt: capturedAt,
            note: note,
            attachmentData: attachment?.data,
            attachmentTypeIdentifier: attachment?.typeIdentifier,
        )
    }
}
