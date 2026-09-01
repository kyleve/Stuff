import ThrowCore

/// Reusable Air & Space configuration draft for onboarding and future View setup.
struct AirAndSpaceSetupDraft {
    /// The complete lifecycle of one onboarding-scoped source candidate.
    enum SourceState {
        struct Signature: Equatable {
            let draft: AircraftSourceValidationDraft
            let generation: UInt64

            var choice: AircraftSourceChoice {
                switch draft.configuration.kind {
                    case .adsbLol: .adsbLol
                    case .readsb: .readsb
                    case .adsbExchangeRapidAPI: .adsbExchange
                    case .flightradar24: .flightradar24
                }
            }
        }

        case editing(choice: AircraftSourceChoice?, generation: UInt64)
        case testing(Signature)
        case validated(draft: ValidatedAircraftSourceDraft, signature: Signature)
        case failed(choice: AircraftSourceChoice, ThrowFailureCategory, generation: UInt64)

        var choice: AircraftSourceChoice? {
            switch self {
                case let .editing(choice, _): choice
                case let .testing(signature), let .validated(_, signature): signature.choice
                case let .failed(choice, _, _): choice
            }
        }

        var presentation: SourceValidationState {
            switch self {
                case .editing:
                    .untested
                case .testing:
                    .testing
                case .validated:
                    .succeeded
                case let .failed(_, failure, _):
                    .failed(failure)
            }
        }

        var validatedDraft: ValidatedAircraftSourceDraft? {
            guard case let .validated(draft, _) = self else { return nil }
            return draft
        }

        var generation: UInt64 {
            switch self {
                case let .editing(_, generation), let .failed(_, _, generation): generation
                case let .testing(signature), let .validated(_, signature): signature.generation
            }
        }
    }

    var readsbURL = "http://readsb.local/tar1090/data/aircraft.json"
    var rapidAPIKey = ""
    var pollingIntervalSeconds = Double(PollingInterval.defaultValue.seconds)
    var selectedMode: ProjectionMode?
    var mapRadius = MapViewport.defaultValue.radius.value
    var minimumElevation = SkyViewport.defaultValue.minimumElevation.degrees
    private(set) var sourceState: SourceState = .editing(choice: nil, generation: 0)

    var sourceChoice: AircraftSourceChoice? {
        sourceState.choice
    }

    var sourceValidation: SourceValidationState {
        sourceState.presentation
    }

    var validatedSource: ValidatedAircraftSourceDraft? {
        sourceState.validatedDraft
    }

    mutating func selectSource(_ choice: AircraftSourceChoice?) {
        guard sourceChoice != choice else { return }
        sourceState = .editing(choice: choice, generation: sourceState.generation &+ 1)
    }

    mutating func invalidateTestedSource() {
        sourceState = .editing(
            choice: sourceChoice,
            generation: sourceState.generation &+ 1,
        )
    }

    mutating func beginSourceTest(
        _ draft: AircraftSourceValidationDraft,
    ) -> SourceState.Signature {
        let signature = SourceState.Signature(
            draft: draft,
            generation: sourceState.generation &+ 1,
        )
        sourceState = .testing(signature)
        return signature
    }

    mutating func failSourceTest(_ failure: ThrowFailureCategory) {
        guard let sourceChoice else { return }
        sourceState = .failed(
            choice: sourceChoice,
            failure,
            generation: sourceState.generation &+ 1,
        )
    }

    @discardableResult
    mutating func resolveSourceTest(
        _ outcome: AircraftSourceValidationOutcome,
        matching signature: SourceState.Signature,
    ) -> Bool {
        guard case let .testing(currentSignature) = sourceState,
              currentSignature == signature
        else { return false }
        switch outcome {
            case let .succeeded(validatedDraft):
                guard validatedDraft.source == signature.draft else {
                    assertionFailure("Source validation returned a different draft")
                    sourceState = .failed(
                        choice: signature.choice,
                        .sourceNotValidated,
                        generation: signature.generation,
                    )
                    return false
                }
                sourceState = .validated(draft: validatedDraft, signature: signature)
                return true
            case let .failed(failure):
                sourceState = .failed(
                    choice: signature.choice,
                    failure,
                    generation: signature.generation,
                )
                return false
            case .cancelled:
                sourceState = .editing(
                    choice: signature.choice,
                    generation: signature.generation,
                )
                return false
        }
    }

    #if DEBUG
        mutating func seedValidatedSource(_ configuration: AircraftSourceConfiguration) {
            let draft = AircraftSourceValidationDraft(configuration: configuration)
            let signature = SourceState.Signature(
                draft: draft,
                generation: sourceState.generation &+ 1,
            )
            sourceState = .validated(
                draft: ValidatedAircraftSourceDraft(source: draft),
                signature: signature,
            )
        }
    #endif

    func mapViewport() throws -> MapViewport {
        try MapViewport(radius: NauticalMiles(value: mapRadius))
    }

    func skyViewport() throws -> SkyViewport {
        try SkyViewport(minimumElevation: ElevationAngle(degrees: minimumElevation))
    }
}
