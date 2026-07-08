import Foundation
@_spi(Testing) import PeriscopeCore

/// Shared fixture event for the tools suites.
struct PhotoLogs: LogEvent {
    var photoID: String
    var message: String {
        "photo \(photoID)"
    }
}

/// A deterministic session for store-backed tests.
func makeSession(startedAt: Date = Date(timeIntervalSinceReferenceDate: 0)) -> LogSession {
    LogSession(
        id: UUID(),
        startedAt: startedAt,
        appVersion: "1.0",
        buildNumber: "42",
        osVersion: "TestOS 1.0",
        deviceModel: "TestDevice1,1",
    )
}

/// An in-memory store with the app → photos → album-1 hierarchy defined.
func makeSeededStore() async throws -> (
    store: PeriscopeStore,
    root: LogScope,
    photos: LogScope,
    album: LogScope
) {
    let store = try await PeriscopeStore.inMemory(session: makeSession())
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
    tags: [LogTagKey: String] = [:],
) -> LogRecord {
    LogRecord(
        date: date,
        event: Message(level: level, text),
        scopes: scopes,
        tags: tags,
    )
}

func date(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: offset)
}

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
