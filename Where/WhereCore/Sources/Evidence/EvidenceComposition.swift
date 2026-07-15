import Foundation
import UniformTypeIdentifiers

extension Evidence {
    /// Compose a new `Evidence` from raw compose-form inputs, shared by the
    /// in-app "Add evidence" form and the Share extension so both map fields to
    /// a record identically instead of each reimplementing the mapping.
    ///
    /// Folds a `.other` free-text label into the kind, trims the note (empty →
    /// `nil`), and classifies the attachment bytes into a content-type hint
    /// (`.other(nil)` when there are no bytes to save). Region is always `nil`
    /// (compose forms don't stamp one); always mints a fresh `id`.
    public static func composed(
        kind: EvidenceKind,
        otherLabel: String,
        capturedAt: Date,
        note: String,
        attachmentData: Data?,
        attachmentTypeIdentifier: String?,
    ) -> Evidence {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType: EvidenceContentType = attachmentData
            .map { EvidenceContentType.classify(data: $0, typeIdentifier: attachmentTypeIdentifier)
            }
            ?? .other(nil)
        return Evidence(
            kind: kind.foldingOtherLabel(otherLabel),
            capturedAt: capturedAt,
            region: nil,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            contentType: contentType,
        )
    }
}

extension EvidenceKind {
    /// When this kind is `.other`, fold in a user-supplied free-text label
    /// (trimmed; empty → no label). Every other kind is returned unchanged.
    public func foldingOtherLabel(_ label: String) -> EvidenceKind {
        guard case .other = self else { return self }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return .other(trimmed.isEmpty ? nil : trimmed)
    }

    /// A reasonable starting kind for an attachment declared as `typeIdentifier`,
    /// so a compose form usually doesn't need the user to change the picker: a
    /// Wallet pass → `.boardingPass`, an image → `.photo`, everything else (and
    /// an unknown or absent type) → `.document`.
    public static func suggested(forTypeIdentifier typeIdentifier: String?) -> EvidenceKind {
        guard let typeIdentifier, let type = UTType(typeIdentifier) else { return .document }
        if type.identifier == "com.apple.pkpass" { return .boardingPass }
        if type.conforms(to: .image) { return .photo }
        return .document
    }
}
