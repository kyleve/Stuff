import Foundation
import PeriscopeCore
import Synchronization

/// One process-owned durable logging session after its store is attached.
public protocol ThrowDurableLoggingSession: Sendable {
    /// Applies Throw's bounded history policy without changing store readiness.
    func pruneHistory() async
}

/// Opens and attaches Throw's one durable logging session.
public protocol ThrowDurableLoggingStarting: ThrowSessionFailureLogging {
    func start() async throws -> any ThrowDurableLoggingSession
}

/// Opens an on-disk Periscope store and routes Throw's process log into it.
public final class PeriscopeThrowDurableLoggingStarter: ThrowDurableLoggingStarting, Sendable {
    private let makeStore: @Sendable () async throws -> PeriscopeStore
    private let softwareCreditsLoadFailure: ThrowSoftwareCreditsLoadFailure?
    private let now: @Sendable () -> Date
    private let preAttachmentRecorder: ThrowPreAttachmentSessionLogRecorder
    private let logger: Log<ThrowSessionLogEvent>

    public convenience init(softwareCreditsLoadFailure: ThrowSoftwareCreditsLoadFailure?) {
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
        @_spi(Testing) public convenience init(
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

        @_spi(Testing) public convenience init(
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
        self.makeStore = makeStore
        softwareCreditsLoadFailure = pendingSoftwareCreditsLoadFailure
        self.now = now
        let recorder = ThrowPreAttachmentSessionLogRecorder(system: system)
        preAttachmentRecorder = recorder
        logger = Log<ThrowRootLogEvent>(recorder: recorder)(ThrowSessionLogEvent.self)
    }

    public func start() async throws -> any ThrowDurableLoggingSession {
        do {
            let store = try await makeStore()
            await preAttachmentRecorder.attach(store)
            logger { .durableLoggingReady }
            recordSoftwareCreditsLoadFailureIfNeeded()
            return PeriscopeThrowDurableLoggingSession(
                store: store,
                now: now,
                logger: logger,
            )
        } catch {
            preAttachmentRecorder.storeOpenFailed()
            recordSoftwareCreditsLoadFailureIfNeeded()
            logger(attachments: [.error(error, name: "open-error")]) {
                .durableLoggingUnavailable(description: String(describing: error))
            }
            throw error
        }
    }

    public func recordColdLaunchFailure(
        at boundary: ThrowSessionLogEvent.ColdLaunchBoundary,
        error: any Error,
    ) {
        ThrowLog.recordColdLaunchFailure(
            at: boundary,
            error: error,
            using: logger,
        )
    }

    public func recordPostLaunchFailure(
        at operation: ThrowSessionLogEvent.PostLaunchOperation,
        error: any Error,
    ) {
        ThrowLog.recordPostLaunchFailure(
            at: operation,
            error: error,
            using: logger,
        )
    }

    private func recordSoftwareCreditsLoadFailureIfNeeded() {
        guard let softwareCreditsLoadFailure else { return }
        ThrowLog.recordSoftwareCreditsLoadFailure(
            softwareCreditsLoadFailure,
            using: logger,
        )
    }
}

/// Retains exact typed session records until the durable store has a safe handoff point.
private final class ThrowPreAttachmentSessionLogRecorder: LogRecorder, Sendable {
    private struct Buffer {
        var scopes: [LogScope] = []
        var scopeIDs: Set<ScopeID> = []
        var recordsSentToExistingSinks: [LogRecord] = []
        var recordsHeldForHandoff: [LogRecord] = []

        mutating func define(_ scope: LogScope) {
            guard scopeIDs.insert(scope.id).inserted else { return }
            scopes.append(scope)
        }
    }

    private enum DeliveryState {
        case buffering(Buffer)
        case handingOff(Buffer)
        case attached
        case osLogOnly
    }

    private let system: Periscope
    private let state = Mutex(DeliveryState.buffering(Buffer()))

    init(system: Periscope) {
        self.system = system
    }

    func defineScope(_ scope: LogScope) {
        state.withLock { state in
            switch state {
                case var .buffering(buffer):
                    buffer.define(scope)
                    state = .buffering(buffer)
                case var .handingOff(buffer):
                    buffer.define(scope)
                    state = .handingOff(buffer)
                case .attached, .osLogOnly:
                    break
            }
            system.defineScope(scope)
        }
    }

    func record(_ record: LogRecord) {
        state.withLock { state in
            switch state {
                case var .buffering(buffer):
                    buffer.recordsSentToExistingSinks.append(record)
                    state = .buffering(buffer)
                    system.record(record)
                case var .handingOff(buffer):
                    buffer.recordsHeldForHandoff.append(record)
                    state = .handingOff(buffer)
                case .attached, .osLogOnly:
                    system.record(record)
            }
        }
    }

    func shouldRecord(level: LogLevel, scopes: [ScopeID]) -> Bool {
        system.shouldRecord(level: level, scopes: scopes)
    }

    func beginSpan(key: SpanKey, span: OpenSpan, began: LogRecord?) -> OpenSpan? {
        system.beginSpan(key: key, span: span, began: began)
    }

    func closeSpan(key: SpanKey) -> OpenSpan? {
        system.closeSpan(key: key)
    }

    func attach(_ durableStore: PeriscopeStore) async {
        let startedHandoff = state.withLock { state -> Bool in
            guard case let .buffering(buffer) = state else { return false }
            state = .handingOff(buffer)
            return true
        }
        precondition(startedHandoff, "Throw's durable log store must attach exactly once")

        await system.flush()
        let replay = state.withLock { state -> Buffer in
            guard case let .handingOff(buffer) = state else {
                preconditionFailure("Throw's durable log handoff changed state unexpectedly")
            }
            return buffer
        }
        await durableStore.defineScopes(replay.scopes)
        await durableStore.write(replay.recordsSentToExistingSinks)
        await durableStore.flush()

        state.withLock { state in
            guard case let .handingOff(buffer) = state else {
                preconditionFailure("Throw's durable log handoff changed state unexpectedly")
            }
            _ = system.add(sink: durableStore)
            state = .attached
            for record in buffer.recordsHeldForHandoff {
                system.record(record)
            }
        }
        await system.flush()
    }

    func storeOpenFailed() {
        state.withLock { state in
            guard case .buffering = state else { return }
            state = .osLogOnly
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
