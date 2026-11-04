import Foundation

/// Opens one physical store only after shared-account preflight. Concurrent and later scopes
/// share its result; cancelling a waiter cannot abandon an open that already started.
@MainActor
public final class DataCompatibilityStorePreparation {
    private final class Opening {
        let task: Task<any WhereStore, any Error>
        init(makeStore: @escaping @Sendable () async throws -> any WhereStore) {
            task = Task { try await makeStore() }
        }
    }

    private enum State {
        case unopened
        case opening(Opening)
        case opened(any WhereStore)
    }

    private var state: State
    private let hasExistingHistory: Bool
    private let makeStore: @Sendable () async throws -> any WhereStore

    public init(
        hasExistingHistory: Bool,
        makeStore: @escaping @Sendable () async throws -> any WhereStore,
    ) {
        self.hasExistingHistory = hasExistingHistory
        self.makeStore = makeStore
        state = .unopened
    }

    init(store: any WhereStore) {
        state = .opened(store)
        hasExistingHistory = false
        makeStore = { store }
    }

    var openedStore: (any WhereStore)? {
        if case let .opened(store) = state { store } else { nil }
    }

    /// Before opening, local file presence is conservative legacy evidence. It can suppress a
    /// new-account activation, but cannot establish account newness or authorize data access.
    func stateBeforeOpening() async throws -> DataCompatibilityStoreState {
        switch state {
            case .unopened:
                DataCompatibilityStoreState(
                    persistedRequiredMajor: nil,
                    recordMajors: [],
                    hasLegacyHistory: hasExistingHistory,
                )
            case .opening, .opened:
                try await open().dataCompatibilityState()
        }
    }

    func open() async throws -> any WhereStore {
        let opening: Opening
        switch state {
            case let .opened(store): return store
            case let .opening(current): opening = current
            case .unopened:
                opening = Opening(makeStore: makeStore)
                state = .opening(opening)
        }
        do {
            let store = try await opening.task.value
            state = .opened(store)
            return store
        } catch {
            if case let .opening(current) = state, current === opening { state = .unopened }
            throw error
        }
    }
}
