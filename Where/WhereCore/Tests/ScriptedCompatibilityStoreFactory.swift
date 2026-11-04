@testable import WhereCore

/// Owns a pending physical open independently of the lifetime of its first caller.
actor ScriptedCompatibilityStoreFactory {
    struct OpenFailure: Error {}
    private let store: any WhereStore
    private let gate: CompatibilityTestGate?
    private var fails = false
    private(set) var openings = 0

    init(store: any WhereStore, gate: CompatibilityTestGate?) {
        self.store = store
        self.gate = gate
    }

    func open() async throws -> any WhereStore {
        openings += 1
        await gate?.suspend()
        if fails { throw OpenFailure() }
        return store
    }

    func setFails(_ fails: Bool) {
        self.fails = fails
    }
}
