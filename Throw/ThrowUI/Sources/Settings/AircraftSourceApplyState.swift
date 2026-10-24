import ThrowCore

/// The complete lifecycle of one settings-scoped aircraft-source candidate.
enum AircraftSourceApplyState {
    struct Signature: Equatable {
        let draft: AircraftSourceValidationDraft
        let generation: UInt64
    }

    case editing(generation: UInt64)
    case testing(signature: Signature, currentDraftGeneration: UInt64)
    case validated(draft: ValidatedAircraftSourceDraft, signature: Signature)
    case applying(
        draft: ValidatedAircraftSourceDraft,
        signature: Signature,
        currentDraftGeneration: UInt64,
    )
    case failed(ThrowFailureCategory, generation: UInt64)
    case succeeded(signature: Signature)
}
