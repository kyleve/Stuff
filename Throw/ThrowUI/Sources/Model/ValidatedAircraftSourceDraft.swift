import ThrowCore

/// A view-scoped, successfully tested source candidate. Replacement secrets
/// stay inside the owning setup model until the user explicitly chooses Use Source.
struct ValidatedAircraftSourceDraft: CustomStringConvertible,
    CustomDebugStringConvertible
{
    let source: AircraftSourceValidationDraft

    var configuration: AircraftSourceConfiguration {
        source.configuration
    }

    var credentialReplacement: AircraftCredentialReplacement? {
        source.credentialReplacement
    }

    var replacementCredential: AircraftCredential? {
        credentialReplacement?.credential
    }

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
