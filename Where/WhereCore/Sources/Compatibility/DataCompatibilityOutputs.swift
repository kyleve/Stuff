import Foundation

/// Serializes external publication with withdrawal for one revocable service world.
public actor DataCompatibilityOutputs {
    private let store: any WhereStore
    let destinations: Destinations
    private enum Lifetime { case active, retiring, retired }
    private var lifetime: Lifetime = .active
    private var isPublishing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private static let logger = WhereLog.root(DataCompatibilityLog.self)

    init(store: any WhereStore, destinations: Destinations) {
        self.store = store
        self.destinations = destinations
    }

    @discardableResult
    func publish(_ operation: @Sendable (DataCompatibilityVersion) async throws -> Void) async
        -> Result<Void, any Error>
    {
        await beginExclusive()
        defer { endExclusive() }
        guard lifetime == .active else {
            Self
                .logger {
                    .accessBlocked(description: DataCompatibilityError.accessRevoked
                        .localizedDescription)
                }
            return .failure(DataCompatibilityError.accessRevoked)
        }
        do {
            try await validate()
            try await operation(.current)
            try await validate()
            return .success(())
        } catch {
            if error is DataCompatibilityError { lifetime = .retiring }
            Self.logger(attachments: [.error(error, name: "compatibility-output-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            await destinations.withdraw()
            if lifetime == .retiring { lifetime = .retired }
            return .failure(error)
        }
    }

    func authorize(_ operation: @Sendable () async -> Bool) async -> Bool {
        do {
            try await validate()
            let result = await operation()
            try await validate()
            return result
        } catch {
            Self.logger(attachments: [.error(error, name: "compatibility-authorization-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            await withdraw()
            return false
        }
    }

    func validate() async throws {
        guard lifetime == .active else { throw DataCompatibilityError.accessRevoked }
        try await store.validateDataAccess()
        guard lifetime == .active else { throw DataCompatibilityError.accessRevoked }
    }

    /// Permanent retirement wins against a publication suspended inside an OS adapter.
    public func retire() async {
        guard lifetime != .retired else { return }
        lifetime = .retiring
        await beginExclusive()
        defer { endExclusive() }
        guard lifetime != .retired else { return }
        await destinations.withdraw()
        lifetime = .retired
    }

    public func withdraw() async {
        await beginExclusive()
        defer { endExclusive() }
        guard lifetime == .active else { return }
        await destinations.withdraw()
    }

    private func beginExclusive() async {
        if isPublishing { await withCheckedContinuation { waiters.append($0) } }
        else { isPublishing = true }
    }

    private func endExclusive() {
        if waiters.isEmpty { isPublishing = false }
        else { waiters.removeFirst().resume() }
    }
}
