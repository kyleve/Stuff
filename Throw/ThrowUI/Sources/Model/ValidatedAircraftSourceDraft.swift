import ThrowCore

/// A view-scoped, successfully tested source candidate. RapidAPI secrets stay
/// inside the owning setup model until the user explicitly chooses Use Source.
struct ValidatedAircraftSourceDraft: CustomStringConvertible,
    CustomDebugStringConvertible
{
    let configuration: AircraftSourceConfiguration
    let replacementCredential: AircraftCredential?

    var description: String {
        "<validated aircraft source draft>"
    }

    var debugDescription: String {
        description
    }
}

enum AircraftSourceValidationOutcome {
    case succeeded(ValidatedAircraftSourceDraft)
    case failed(ThrowFailureCategory)
    case cancelled
}
