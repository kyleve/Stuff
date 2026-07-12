import WhereCore

/// Presentation helpers for `EvidenceKind`: the SF Symbol and localized display
/// name the evidence list, detail, and compose form render. Lives in WhereUI so
/// WhereCore stays free of UI/string concerns.
extension EvidenceKind {
    /// SF Symbol that visually stands in for this kind in list rows and the
    /// kind picker.
    var symbolName: String {
        switch self {
            case .planeTicket: "airplane"
            case .boardingPass: "ticket"
            case .hotelReceipt: "bed.double"
            case .carRental: "car"
            case .rideshare: "car.side"
            case .photo: "photo"
            case .document: "doc"
            case .email: "envelope"
            case .other: "paperclip"
        }
    }

    /// Localized, user-facing name (the `.other` label when one was supplied).
    var displayName: String {
        Strings.evidenceKind(self)
    }
}
