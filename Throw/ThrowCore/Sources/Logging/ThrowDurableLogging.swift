import Foundation
import PeriscopeCore

/// One process-owned durable logging session after its store is attached.
public protocol ThrowDurableLoggingSession: Sendable {
    /// Applies Throw's bounded history policy without changing store readiness.
    func pruneHistory() async
}

/// Opens and attaches Throw's one durable logging session.
public protocol ThrowDurableLoggingStarting: Sendable {
    func start() async throws -> any ThrowDurableLoggingSession
}

/// Opens an on-disk Periscope store and routes Throw's process log into it.
public struct PeriscopeThrowDurableLoggingStarter: ThrowDurableLoggingStarting {
    private let system: Periscope
    private let makeStore: @Sendable () async throws -> PeriscopeStore
    private let softwareCreditsLoadFailure: ThrowSoftwareCreditsLoadFailure?
    private let now: @Sendable () -> Date
    private let logger: Log<ThrowSessionLogEvent>

    public init(softwareCreditsLoadFailure: ThrowSoftwareCreditsLoadFailure?) {
        self.init(
            system: .shared,
            pendingSoftwareCreditsLoadFailure: softwareCreditsLoadFailure,
            now: { Date() },
            makeStore: {
                try await PeriscopeStore.make(
                    storage: .onDisk,
                    session: .current(attributes: [:]),
                )
            },
        )
    }

    #if DEBUG
        @_spi(Testing) public init(
            system: Periscope,
            storage: PeriscopeStore.Storage,
            softwareCreditsLoadFailure: ThrowSoftwareCreditsLoadFailure?,
            now: @escaping @Sendable () -> Date,
        ) {
            self.init(
                system: system,
                pendingSoftwareCreditsLoadFailure: softwareCreditsLoadFailure,
                now: now,
                makeStore: {
                    try await PeriscopeStore.make(
                        storage: storage,
                        session: .current(attributes: [:]),
                    )
                },
            )
        }

        @_spi(Testing) public init(
            system: Periscope,
            softwareCreditsLoadFailure: ThrowSoftwareCreditsLoadFailure?,
            now: @escaping @Sendable () -> Date,
            makeStore: @escaping @Sendable () async throws -> PeriscopeStore,
        ) {
            self.init(
                system: system,
                pendingSoftwareCreditsLoadFailure: softwareCreditsLoadFailure,
                now: now,
                makeStore: makeStore,
            )
        }
    #endif

    private init(
        system: Periscope,
        pendingSoftwareCreditsLoadFailure: ThrowSoftwareCreditsLoadFailure?,
        now: @escaping @Sendable () -> Date,
        makeStore: @escaping @Sendable () async throws -> PeriscopeStore,
    ) {
        self.system = system
        self.makeStore = makeStore
        softwareCreditsLoadFailure = pendingSoftwareCreditsLoadFailure
        self.now = now
        logger = Log<ThrowRootLogEvent>(recorder: system)(ThrowSessionLogEvent.self)
    }

    public func start() async throws -> any ThrowDurableLoggingSession {
        do {
            let store = try await makeStore()
            _ = system.add(sink: store)
            logger { .durableLoggingReady }
            recordSoftwareCreditsLoadFailureIfNeeded()
            return PeriscopeThrowDurableLoggingSession(
                store: store,
                now: now,
                logger: logger,
            )
        } catch {
            recordSoftwareCreditsLoadFailureIfNeeded()
            logger(attachments: [.error(error, name: "open-error")]) {
                .durableLoggingUnavailable(description: String(describing: error))
            }
            throw error
        }
    }

    private func recordSoftwareCreditsLoadFailureIfNeeded() {
        guard let softwareCreditsLoadFailure else { return }
        ThrowLog.recordSoftwareCreditsLoadFailure(
            softwareCreditsLoadFailure,
            using: logger,
        )
    }
}

private actor PeriscopeThrowDurableLoggingSession: ThrowDurableLoggingSession {
    private static let retentionWindow: TimeInterval = 100 * 24 * 60 * 60
    private static let retainedEventLimit = 50000

    private let store: PeriscopeStore
    private let now: @Sendable () -> Date
    private let logger: Log<ThrowSessionLogEvent>

    init(
        store: PeriscopeStore,
        now: @escaping @Sendable () -> Date,
        logger: Log<ThrowSessionLogEvent>,
    ) {
        self.store = store
        self.now = now
        self.logger = logger
    }

    func pruneHistory() async {
        do {
            let cutoff = now().addingTimeInterval(-Self.retentionWindow)
            let expired = try await store.pruneEvents(olderThan: cutoff)
            let overflow = try await store.pruneEvents(
                keepingNewest: Self.retainedEventLimit,
            )
            logger {
                .durableLoggingHistoryPruned(
                    expiredEventCount: expired,
                    overflowEventCount: overflow,
                )
            }
        } catch {
            logger(attachments: [.error(error, name: "prune-error")]) {
                .durableLoggingHistoryPruneFailed(
                    description: String(describing: error),
                )
            }
        }
    }
}
