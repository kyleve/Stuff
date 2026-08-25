import Observation
import ThrowCore

@MainActor
@Observable
final class AircraftSourceSettingsModel {
    private let session: ThrowSession

    var choice: AircraftSourceChoice {
        didSet {
            guard oldValue != choice else { return }
            invalidateTestedDraft()
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
    var isEditingCredential: Bool

    private var validatedDraft: ValidatedAircraftSourceDraft?
    private var testGeneration: UInt64 = 0

    init(session: ThrowSession) {
        self.session = session
        choice = session.sourceChoice
        readsbURL = session.readsbURL
        pollingIntervalSeconds = Double(session.pollingIntervalSeconds)
        if case .missing = session.rapidAPICredentialState {
            isEditingCredential = true
        } else {
            isEditingCredential = false
        }
    }

    var credentialState: CredentialState {
        session.rapidAPICredentialState
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

    var canUseSource: Bool {
        validation.isSuccessful && validatedDraft != nil
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

    func useSource() async {
        guard validation.isSuccessful, let validatedDraft else { return }
        if await session.useSource(validatedDraft) {
            isEditingCredential = false
            rapidAPIKey = ""
            self.validatedDraft = nil
            validation = .untested
        }
    }

    func deleteCredential() async {
        await session.deleteRapidAPICredential()
        rapidAPIKey = ""
        invalidateTestedDraft()
        isEditingCredential = true
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
}
