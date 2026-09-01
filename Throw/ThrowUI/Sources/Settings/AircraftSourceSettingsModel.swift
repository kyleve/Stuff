import Observation
import ThrowCore

@MainActor
@Observable
final class AircraftSourceSettingsModel {
    private let session: ThrowSession

    var choice: AircraftSourceChoice {
        didSet {
            guard oldValue != choice else { return }
            rapidAPIKey = ""
            invalidateTestedDraft()
            synchronizeCredentialEditingState()
            flightradar24UsageState = .idle
        }
    }

    var readsbURL: String {
        didSet {
            guard oldValue != readsbURL else { return }
            invalidateTestedDraft()
        }
    }

    var rapidAPIKey = "" {
        didSet {
            guard oldValue != rapidAPIKey, rapidAPIKey.isEmpty == false else { return }
            invalidateTestedDraft()
        }
    }

    var pollingIntervalSeconds: Double {
        didSet {
            guard oldValue != pollingIntervalSeconds else { return }
            invalidateTestedDraft()
        }
    }

    var isEditingCredential = false
    var flightradar24UsageState: Flightradar24UsageLoadState = .idle

    private var applyState: AircraftSourceApplyState = .editing(generation: 0)
    private var draftGeneration: UInt64 = 0

    init(session: ThrowSession) {
        self.session = session
        let initialChoice = session.sourceChoice
        choice = initialChoice
        readsbURL = session.readsbURL
        pollingIntervalSeconds = Double(session.pollingIntervalSeconds)
        synchronizeCredentialEditingState()
    }

    var credentialState: CredentialState {
        switch choice {
            case .adsbExchange: session.rapidAPICredentialState
            case .flightradar24: session.flightradar24CredentialState
            case .adsbLol, .readsb: .missing
        }
    }

    var settingsFailure: String? {
        session.settingsFailure
    }

    var usageEstimate: ADSBExchangeUsageEstimate {
        session.adsbExchangeUsageEstimate(intervalSeconds: Int(pollingIntervalSeconds))
    }

    var requestsPerHour: Int {
        usageEstimate.displayedRequestsPerHour
    }

    var thirtyDayUpperBound: Int {
        usageEstimate.displayedThirtyDayUpperBound
    }

    var exceedsPublishedAllowance: Bool {
        usageEstimate.exceedsPublishedAllowance
    }

    var flightradar24CreditEstimate: Flightradar24CreditEstimate? {
        guard case let .loaded(report) = flightradar24UsageState else { return nil }
        return session.flightradar24CreditEstimate(
            report: report,
            intervalSeconds: Int(pollingIntervalSeconds),
        )
    }

    var canUseSource: Bool {
        if case .validated = applyState { true } else { false }
    }

    var canTestAndApply: Bool {
        guard isOperationInFlight == false else { return false }
        if isCredentialSource, isEditingCredential {
            return rapidAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return true
    }

    var validation: SourceValidationState {
        switch applyState {
            case .editing:
                .untested
            case let .testing(signature, currentDraftGeneration):
                currentDraftGeneration == signature.generation ? .testing : .untested
            case .validated, .succeeded:
                .succeeded
            case let .applying(_, signature, currentDraftGeneration):
                currentDraftGeneration == signature.generation ? .testing : .untested
            case let .failed(failure, _):
                .failed(failure)
        }
    }

    var isOperationInFlight: Bool {
        switch applyState {
            case .testing, .applying:
                true
            case .editing, .validated, .failed, .succeeded:
                false
        }
    }

    var isCredentialSource: Bool {
        choice == .adsbExchange || choice == .flightradar24
    }

    func test() async {
        guard isOperationInFlight == false else { return }
        draftGeneration &+= 1
        let generation = draftGeneration
        let draft: AircraftSourceValidationDraft
        do {
            draft = try session.sourceValidationDraft(
                choice: choice,
                readsbURL: readsbURL,
                rapidAPIKey: rapidAPIKey,
                pollingIntervalSeconds: Int(pollingIntervalSeconds),
            )
        } catch let failure as AircraftSourceFailure {
            applyState = .failed(failure.presentationCategory, generation: generation)
            return
        } catch {
            applyState = .failed(.sourceNotValidated, generation: generation)
            return
        }
        let signature = AircraftSourceApplyState.Signature(
            draft: draft,
            generation: generation,
        )
        applyState = .testing(
            signature: signature,
            currentDraftGeneration: generation,
        )
        let outcome = await session.testSource(draft)
        guard case let .testing(currentSignature, currentDraftGeneration) = applyState,
              currentSignature == signature
        else { return }
        guard currentDraftGeneration == signature.generation else {
            applyState = .editing(generation: currentDraftGeneration)
            return
        }
        switch outcome {
            case let .succeeded(validatedDraft):
                guard validatedDraft.source == signature.draft else {
                    assertionFailure("Source validation returned a different draft")
                    applyState = .failed(.sourceNotValidated, generation: generation)
                    return
                }
                applyState = .validated(draft: validatedDraft, signature: signature)
                rapidAPIKey = ""
            case let .failed(failure):
                applyState = .failed(failure, generation: generation)
            case .cancelled:
                applyState = .editing(generation: generation)
        }
    }

    func loadFlightradar24Usage() async {
        guard choice == .flightradar24, case .saved = credentialState else {
            flightradar24UsageState = .idle
            return
        }
        guard flightradar24UsageState != .loading else { return }
        flightradar24UsageState = .loading
        do {
            let report = try await session.loadFlightradar24Usage()
            try Task.checkCancellation()
            flightradar24UsageState = .loaded(report)
        } catch is CancellationError {
            flightradar24UsageState = .idle
        } catch Flightradar24UsageError.rateLimited {
            flightradar24UsageState = .rateLimited
        } catch AircraftSourceFailure.decoding {
            flightradar24UsageState = .unexpectedResponse
        } catch let failure as AircraftSourceFailure {
            flightradar24UsageState = .failed(failure.presentationCategory)
        } catch {
            flightradar24UsageState = .failed(.unknown)
        }
    }

    func useSource() async {
        guard case let .validated(validatedDraft, signature) = applyState else { return }
        applyState = .applying(
            draft: validatedDraft,
            signature: signature,
            currentDraftGeneration: signature.generation,
        )
        let applied = await session.useSource(validatedDraft)
        guard case let .applying(
            currentDraft,
            currentSignature,
            currentDraftGeneration,
        ) = applyState,
            currentSignature == signature,
            currentDraft.source == validatedDraft.source
        else { return }
        guard currentDraftGeneration == signature.generation else {
            applyState = .editing(generation: currentDraftGeneration)
            return
        }
        guard applied else {
            applyState = .failed(.unknown, generation: signature.generation)
            return
        }
        isEditingCredential = false
        rapidAPIKey = ""
        applyState = .succeeded(signature: signature)
        if signature.draft.configuration.kind == .flightradar24 {
            flightradar24UsageState = .idle
            await loadFlightradar24Usage()
        }
    }

    func testAndApply() async {
        guard canTestAndApply else { return }
        await test()
        guard canUseSource else { return }
        await useSource()
    }

    func deleteCredential() async {
        let deleted: Bool
        switch choice {
            case .adsbExchange:
                deleted = await session.deleteRapidAPICredential()
            case .flightradar24:
                deleted = await session.deleteFlightradar24Credential()
            case .adsbLol, .readsb:
                return
        }
        guard deleted else { return }
        rapidAPIKey = ""
        invalidateTestedDraft()
        isEditingCredential = true
        flightradar24UsageState = .idle
    }

    func replaceCredential() {
        rapidAPIKey = ""
        invalidateTestedDraft()
        isEditingCredential = true
    }

    func cancelCredentialReplacement() {
        rapidAPIKey = ""
        invalidateTestedDraft()
        if case .saved = credentialState {
            isEditingCredential = false
        }
    }

    func discardTestedDraft() {
        rapidAPIKey = ""
        invalidateTestedDraft()
    }

    private func invalidateTestedDraft() {
        draftGeneration &+= 1
        switch applyState {
            case let .testing(signature, _):
                applyState = .testing(
                    signature: signature,
                    currentDraftGeneration: draftGeneration,
                )
            case let .applying(draft, signature, _):
                applyState = .applying(
                    draft: draft,
                    signature: signature,
                    currentDraftGeneration: draftGeneration,
                )
            case .editing, .validated, .failed, .succeeded:
                applyState = .editing(generation: draftGeneration)
        }
    }

    private func synchronizeCredentialEditingState() {
        guard isCredentialSource else {
            isEditingCredential = false
            return
        }
        if case .missing = credentialState {
            isEditingCredential = true
        } else {
            isEditingCredential = false
        }
    }
}
