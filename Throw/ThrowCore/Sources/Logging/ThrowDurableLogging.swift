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
    private let storage: PeriscopeStore.Storage
    private let now: @Sendable () -> Date
    private let logger: Log<ThrowSessionLogEvent>

    public init() {
        self.init(
            system: .shared,
            storage: .onDisk,
            now: { Date() },
        )
    }

    #if DEBUG
        @_spi(Testing) public init(
            system: Periscope,
            storage: PeriscopeStore.Storage,
            now: @escaping @Sendable () -> Date,
        ) {
            self.system = system
            self.storage = storage
            self.now = now
            logger = Log<ThrowRootLogEvent>(recorder: system)(ThrowSessionLogEvent.self)
        }
    #else
        private init(
            system: Periscope,
            storage: PeriscopeStore.Storage,
            now: @escaping @Sendable () -> Date,
        ) {
            self.system = system
            self.storage = storage
            self.now = now
            logger = Log<ThrowRootLogEvent>(recorder: system)(ThrowSessionLogEvent.self)
        }
    #endif

    public func start() async throws -> any ThrowDurableLoggingSession {
        do {
            let store = try await PeriscopeStore.make(
                storage: storage,
                session: .current(attributes: [:]),
            )
            _ = system.add(sink: store)
            logger { .durableLoggingReady }
            return PeriscopeThrowDurableLoggingSession(
                store: store,
                now: now,
                logger: logger,
            )
        } catch {
            logger(attachments: [.error(error, name: "open-error")]) {
                .durableLoggingUnavailable(description: String(describing: error))
            }
            throw error
        }
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
