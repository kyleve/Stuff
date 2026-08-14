import Foundation
import os
import PeriscopeCore

/// An in-memory `LogRecorder` that captures everything for assertions.
final class RecordingRecorder: LogRecorder, Sendable {
    private struct State {
        var scopes: [LogScope] = []
        var records: [LogRecord] = []
        var openSpans: [SpanKey: OpenSpan] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var definedScopes: [LogScope] {
        state.withLock(\.scopes)
    }

    var records: [LogRecord] {
        state.withLock(\.records)
    }

    func defineScope(_ scope: LogScope) {
        state.withLock { $0.scopes.append(scope) }
    }

    func record(_ record: LogRecord) {
        state.withLock { $0.records.append(record) }
    }

    func shouldRecord(level _: LogLevel, scopes _: [ScopeID]) -> Bool {
        true
    }

    func beginSpan(key: SpanKey, span: OpenSpan, began: LogRecord?) -> OpenSpan? {
        state.withLock { state in
            let prior = state.openSpans.removeValue(forKey: key)
            state.openSpans[key] = span
            if let began {
                state.records.append(began)
            }
            return prior
        }
    }

    func closeSpan(key: SpanKey) -> OpenSpan? {
        state.withLock { $0.openSpans.removeValue(forKey: key) }
    }
}

/// A deterministic SplitMix64 generator so fuzz tests replay failures
/// exactly from their seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Polls `predicate` until it holds or `timeout` elapses, returning whether
/// it ever held — condition-based waiting, never a fixed sleep.
func waitUntil(
    timeout: Duration = .seconds(5),
    _ predicate: @Sendable () -> Bool,
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return predicate()
}

/// A `LogSink` whose `write` blocks until `open()` — used to hold the drain
/// task mid-delivery so tests can deterministically overflow the pending
/// queue.
final class GateSink: LogSink, Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
        var batchCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Batches received so far (counted before blocking).
    var batchCount: Int {
        state.withLock(\.batchCount)
    }

    /// Release every blocked `write` and let future writes pass through.
    func open() {
        let waiters = state.withLock { state in
            state.isOpen = true
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func defineScopes(_: [LogScope]) async {}

    func write(_: [LogRecord]) async {
        state.withLock { $0.batchCount += 1 }
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state in
                if state.isOpen {
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func flush() async {}
}

/// An in-memory `LogSink` that captures deliveries in order for assertions.
final class CapturingSink: LogSink, Sendable {
    enum Delivery {
        case scopes([LogScope])
        case records([LogRecord])
    }

    private struct State {
        var deliveries: [Delivery] = []
        var flushCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var deliveries: [Delivery] {
        state.withLock(\.deliveries)
    }

    var flushCount: Int {
        state.withLock(\.flushCount)
    }

    var definedScopes: [LogScope] {
        deliveries.flatMap { delivery -> [LogScope] in
            guard case let .scopes(scopes) = delivery else { return [] }
            return scopes
        }
    }

    var records: [LogRecord] {
        deliveries.flatMap { delivery -> [LogRecord] in
            guard case let .records(records) = delivery else { return [] }
            return records
        }
    }

    func defineScopes(_ scopes: [LogScope]) async {
        state.withLock { $0.deliveries.append(.scopes(scopes)) }
    }

    func write(_ records: [LogRecord]) async {
        state.withLock { $0.deliveries.append(.records(records)) }
    }

    func flush() async {
        state.withLock { $0.flushCount += 1 }
    }
}

extension LogSession {
    /// A deterministic session for store tests.
    static func fixture(
        id: UUID = UUID(),
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 0),
        attributes: [LogSessionAttributeKey: String] = [:],
    ) -> LogSession {
        LogSession(
            id: id,
            startedAt: startedAt,
            appVersion: "1.0",
            buildNumber: "42",
            osVersion: "TestOS 1.0",
            deviceModel: "TestDevice1,1",
            attributes: attributes,
        )
    }
}

/// A deterministic instant `offset` seconds into the reference era, for
/// store and journal tests.
func date(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: offset)
}

/// A freeform record with an explicit date, for deterministic store tests.
func makeRecord(
    _ text: String,
    level: LogLevel = .info,
    date: Date,
    scopes: [ScopeID],
) -> LogRecord {
    LogRecord(
        date: date,
        event: Message(
            level: .restricted(.technicalState, level),
            text: .restricted(.arbitraryText, text),
        ),
        scopes: scopes,
    )
}

func makeMessage(_ text: String, level: LogLevel = .info) -> Message {
    Message(
        level: .restricted(.technicalState, level),
        text: .restricted(.arbitraryText, text),
    )
}

/// Builds an ambient event while keeping its complete restricted schema explicit.
func makeAmbientEvent(
    kind: AmbientKind,
    value: [String: AmbientValue],
    level: LogLevel = .info,
    reporting: AmbientEvent.Reporting = .state,
) -> AmbientEvent {
    AmbientEvent(
        kind: .restricted(.technicalState, kind),
        value: .restricted(.domainValue, value),
        level: .restricted(.technicalState, level),
        reporting: .restricted(.technicalState, reporting),
    )
}

func makeSpanBegan(
    spanID: SpanID,
    name: String,
    lifetime: SpanLifetime,
    relaunchPolicy: SpanRelaunchPolicy,
) -> SpanBegan {
    let mode: SpanBegan.LifetimeMode
    let budget: Duration?
    switch lifetime {
        case .scoped:
            mode = .scoped
            budget = nil
        case let .bounded(value):
            mode = .bounded
            budget = value
        case .indefinite:
            mode = .indefinite
            budget = nil
    }
    return SpanBegan(
        spanID: .restricted(.identifier, spanID),
        name: .restricted(.technicalState, name),
        lifetimeMode: .restricted(.technicalState, mode),
        budget: .shared(.duration, budget),
        relaunchPolicy: .shared(.category, relaunchPolicy),
    )
}

func makeSpanEnded(
    spanID: SpanID,
    name: String,
    duration: Duration?,
    exit: SpanExit,
) -> SpanEnded {
    SpanEnded(
        spanID: .restricted(.identifier, spanID),
        name: .restricted(.technicalState, name),
        duration: .shared(.duration, duration),
        exitMode: .shared(.category, exit.mode),
        exitReason: .restricted(.errorDetails, exit.reason),
    )
}

func makeSpanOverdue(spanID: SpanID, name: String, budget: Duration) -> SpanOverdue {
    SpanOverdue(
        spanID: .restricted(.identifier, spanID),
        name: .restricted(.technicalState, name),
        budget: .shared(.duration, budget),
    )
}

/// Shared fixture events used across suites.
@LogScope("AppLogs")
enum AppLogs {
    @LogEvent("event", message: "app")
    struct Event {}
}

@LogScope("PhotoLogs")
enum PhotoLogs {
    @LogEvent("event", level: .notice)
    struct Event {
        @LogField("photo_id", exposure: .restricted, kind: .identifier)
        var photoID: String

        var message: String {
            "photo \(photoID)"
        }
    }
}

func makePhotoEvent(_ photoID: String) -> PhotoLogs.Event {
    PhotoLogs.Event(photoID: .restricted(.identifier, photoID))
}
