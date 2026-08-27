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

    var validation: SourceValidationState = .untested
    var isEditingCredential = false
    var flightradar24UsageState: Flightradar24UsageLoadState = .idle

    private var validatedDraft: ValidatedAircraftSourceDraft?
    private var testGeneration: UInt64 = 0

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
        validation.isSuccessful && validatedDraft != nil
    }

    var canTestAndApply: Bool {
        guard validation != .testing else { return false }
        if isCredentialSource, isEditingCredential {
            return rapidAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return true
    }

    var isCredentialSource: Bool {
        choice == .adsbExchange || choice == .flightradar24
    }

    func test() async {
        testGeneration &+= 1
        let generation = testGeneration
        validatedDraft = nil
        validation = .testing
        let outcome = await session.testSource(
            choice: choice,
            readsbURL: readsbURL,
            rapidAPIKey: rapidAPIKey,
            pollingIntervalSeconds: Int(pollingIntervalSeconds),
        )
        guard generation == testGeneration else { return }
        switch outcome {
            case let .succeeded(draft):
                validatedDraft = draft
                validation = .succeeded
                rapidAPIKey = ""
            case let .failed(failure):
                validation = .failed(failure)
            case .cancelled:
                validation = .untested
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
        guard validation.isSuccessful, let validatedDraft else { return }
        if await session.useSource(validatedDraft) {
            isEditingCredential = false
            rapidAPIKey = ""
            self.validatedDraft = nil
            validation = .succeeded
            if choice == .flightradar24 {
                flightradar24UsageState = .idle
                await loadFlightradar24Usage()
            }
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
        testGeneration &+= 1
        validatedDraft = nil
        validation = .untested
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
