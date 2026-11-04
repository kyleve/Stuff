import CloudKit
@testable import WhereCore

/// Two transport instances share this conditional server. Separate gates expose each await;
/// no fake transport shortcut can bypass the production initialization or account checks.
actor ScriptedDataCompatibilityControlDatabase: DataCompatibilityControlDatabase {
    private var account = ScriptedSharedDataCompatibilityTransport.account
    private var currentHead: SharedDataCompatibilityState?
    private var legacyZone: Bool
    private var zoneError: (any Error)?
    private var saveGate: CompatibilityTestGate?
    private var preparationGate: CompatibilityTestGate?
    private var headGate: CompatibilityTestGate?
    private var responseError: (any Error)?
    private(set) var committedSaves = 0

    init(legacyZone: Bool) {
        self.legacyZone = legacyZone
    }

    func accountID() async throws -> DataCompatibilityAccountID {
        account
    }

    func head(accountID: DataCompatibilityAccountID) async throws -> SharedDataCompatibilityState? {
        guard accountID == account else { throw DataCompatibilityError.accountChanged }
        let value = currentHead
        let gate = headGate
        headGate = nil
        if let gate { await gate.suspend() }
        return value
    }

    func hasLegacyZone() async throws -> Bool {
        if let zoneError { throw zoneError }
        return legacyZone
    }

    func createMirrorZone() {
        legacyZone = true
    }

    func prepareControlZone() async throws {
        let gate = preparationGate
        preparationGate = nil
        if let gate { await gate.suspend() }
    }

    func saveHead(
        accountID: DataCompatibilityAccountID,
        requiredMajor: UInt,
        expectedRevision: SharedDataCompatibilityState.Revision?,
    ) async throws -> SharedDataCompatibilityState {
        let gate = saveGate
        saveGate = nil
        if let gate { await gate.suspend() }
        guard accountID == account else { throw DataCompatibilityError.accountChanged }
        guard currentHead?.revision == expectedRevision,
              (currentHead?.requiredMajor ?? 0) <= requiredMajor
        else { throw DataCompatibilityError.concurrentChange }
        committedSaves += 1
        let state = SharedDataCompatibilityState(
            accountID: account,
            requiredMajor: requiredMajor,
            revision: .init(rawValue: String(committedSaves)),
        )
        currentHead = state
        if let responseError {
            self.responseError = nil
            throw responseError
        }
        return state
    }

    func holdSave(_ gate: CompatibilityTestGate) {
        saveGate = gate
    }

    func holdPreparation(_ gate: CompatibilityTestGate) {
        preparationGate = gate
    }

    func holdHead(_ gate: CompatibilityTestGate) {
        headGate = gate
    }

    func failZoneListing(_ error: any Error) {
        zoneError = error
    }

    func loseSaveResponse(_ error: any Error) {
        responseError = error
    }

    func switchAccount() {
        account = .init(rawValue: "another-account"); currentHead = nil
    }
}
