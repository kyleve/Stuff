import Foundation
@_spi(Testing) import PeriscopeCore
import TestHostSupport
import UIKit

/// Shared fixture event for the tools suites.
struct PhotoLogs: LogEvent {
    var photoID: String
    var message: String {
        "photo \(photoID)"
    }
}

/// A deterministic session for store-backed tests.
func makeSession(
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

/// An in-memory store with the app → photos → album-1 hierarchy defined.
func makeSeededStore(
    sessionAttributes: [LogSessionAttributeKey: String] = [:],
) async throws -> (
    store: PeriscopeStore,
    root: LogScope,
    photos: LogScope,
    album: LogScope
) {
    let store = try await PeriscopeStore.inMemory(
        session: makeSession(attributes: sessionAttributes),
    )
    let root = LogScope.root(named: "app")
    let photos = root.child(named: "photos")
    let album = photos.child(named: "album-1")
    await store.defineScopes([root, photos, album])
    return (store, root, photos, album)
}

/// A freeform record with an explicit date.
func makeRecord(
    _ text: String,
    level: LogLevel = .info,
    date: Date,
    scopes: [ScopeID],
    tags: [LogTag] = [],
) -> LogRecord {
    LogRecord(
        date: date,
        event: Message(
            level: .restricted(.technicalState, level),
            text: .restricted(.arbitraryText, text),
        ),
        scopes: scopes,
        tags: tags,
    )
}

func classifiedMessage(_ text: String, level: LogLevel = .info) -> Message {
    Message(
        level: .restricted(.technicalState, level),
        text: .restricted(.arbitraryText, text),
    )
}

func date(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: offset)
}

/// A `SpanBegan` record for the span-tree suites.
func spanBegan(
    _ id: SpanID,
    name: String,
    at date: Date,
    scope: ScopeID,
) -> LogRecord {
    LogRecord(
        date: date,
        event: SpanBegan(
            spanID: .restricted(.identifier, id),
            name: .restricted(.technicalState, name),
            lifetimeMode: .restricted(.technicalState, .scoped),
            budget: .shared(.duration, nil),
            relaunchPolicy: .shared(.category, .endsWithProcess),
        ),
        scopes: [scope],
    )
}

/// A `SpanEnded` record for the span-tree suites.
func spanEnded(
    _ id: SpanID,
    name: String,
    at date: Date,
    duration: Duration,
    exit: SpanExit = .success,
    scope: ScopeID,
) -> LogRecord {
    LogRecord(
        date: date,
        event: classifiedSpanEnded(spanID: id, name: name, duration: duration, exit: exit),
        scopes: [scope],
    )
}

/// A stored span event as the span tooling reads it back, for the cases a live
/// store can't produce: `payload` is passed through verbatim, so a suite can
/// hand the models the on-disk corruption they have to report honestly.
func storedSpanEvent(
    eventName: String,
    spanID: SpanID,
    message: String,
    at date: Date,
    payload: Data,
    exitMode: SpanExit.Mode? = nil,
) -> StoredLogEvent {
    StoredLogEvent(
        id: UUID(),
        date: date,
        sequence: 0,
        level: .info,
        eventName: eventName,
        eventVersion: 1,
        message: message,
        payload: payload,
        scopes: [LogScope.root(named: "app").id],
        tags: [],
        spanID: spanID,
        spanExitMode: exitMode,
        callSite: nil,
        externalID: nil,
        attachments: [],
        sessionID: UUID(),
        ambientSnapshotID: nil,
    )
}

/// A stored `SpanBegan` row carrying a real, decodable payload.
func storedSpanBegan(_ id: SpanID, name: String, at date: Date) throws -> StoredLogEvent {
    try storedSpanEvent(
        eventName: SpanBegan.eventName,
        spanID: id,
        message: "▶ \(name)",
        at: date,
        payload: JSONEncoder().encode(
            SpanBegan(
                spanID: .restricted(.identifier, id),
                name: .restricted(.technicalState, name),
                lifetimeMode: .restricted(.technicalState, .scoped),
                budget: .shared(.duration, nil),
                relaunchPolicy: .shared(.category, .endsWithProcess),
            ),
        ),
    )
}

/// A stored `SpanEnded` row carrying a real, decodable payload.
func storedSpanEnded(
    _ id: SpanID,
    name: String,
    at date: Date,
    duration: Duration?,
    exit: SpanExit,
) throws -> StoredLogEvent {
    try storedSpanEvent(
        eventName: SpanEnded.eventName,
        spanID: id,
        message: "◀ \(name)",
        at: date,
        payload: JSONEncoder().encode(
            classifiedSpanEnded(spanID: id, name: name, duration: duration, exit: exit),
        ),
        exitMode: exit.mode,
    )
}

func classifiedSpanEnded(
    spanID id: SpanID,
    name: String,
    duration: Duration?,
    exit: SpanExit,
) -> SpanEnded {
    SpanEnded(
        spanID: .restricted(.identifier, id),
        name: .restricted(.technicalState, name),
        duration: .shared(.duration, duration),
        exitMode: .shared(.category, exit.mode),
        exitReason: .restricted(.errorDetails, exit.reason),
    )
}

func classifiedSpanBegan(
    spanID id: SpanID,
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
        spanID: .restricted(.identifier, id),
        name: .restricted(.technicalState, name),
        lifetimeMode: .restricted(.technicalState, mode),
        budget: .shared(.duration, budget),
        relaunchPolicy: .shared(.category, relaunchPolicy),
    )
}

/// Bytes that are not JSON — a persisted payload is `JSONEncoder` output, so
/// these stand in for on-disk corruption rather than a shape change.
let unreadablePayload = Data([0xFF, 0x00])

/// Polls `predicate` on the main actor until it holds or the budget runs
/// out — models reload on their own tasks, so tests wait for the resulting
/// state rather than racing it.
@MainActor
func waitUntil(_ predicate: () -> Bool) async -> Bool {
    for _ in 0 ..< 2000 {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return predicate()
}

/// The async-predicate form, for conditions that consult an actor
/// (e.g. store observer counts).
@MainActor
func waitUntil(_ predicate: () async -> Bool) async -> Bool {
    for _ in 0 ..< 2000 {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await predicate()
}

/// `TestHostSupport.show` with an async body: hosts `viewController` in the
/// test host's hierarchy for the duration of `body`, so tests can await
/// SwiftUI/task work while the view stays on screen.
@MainActor
func showHosted<ViewController: UIViewController>(
    _ viewController: ViewController,
    _ body: (ViewController) async throws -> Void,
) async throws {
    guard let rootVC = hostKeyWindow()?.rootViewController else {
        throw TestHostError("No root view controller in test host.")
    }
    // Match TestHostSupport.show: run window animations at 100x so tests
    // never wait on real transition durations.
    defer { rootVC.view.window?.layer.speed = 1 }
    rootVC.view.window?.layer.speed = 100
    rootVC.addChild(viewController)
    viewController.view.frame = rootVC.view.bounds
    rootVC.view.addSubview(viewController.view)
    viewController.view.layoutIfNeeded()
    viewController.didMove(toParent: rootVC)
    defer {
        viewController.willMove(toParent: nil)
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
    }
    try await body(viewController)
}
