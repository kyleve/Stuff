import Foundation
@testable import WhereCore

extension BackupCoordinator {
    /// Settings-purpose convenience kept in the test target so production callers must always
    /// name the import purpose explicitly.
    func importBackup(
        from url: URL,
        strategy: ImportStrategy,
        onProgress: @Sendable (Double) -> Void = { _ in },
    ) async throws -> ImportSummary {
        try await importBackup(
            from: url,
            strategy: strategy,
            purpose: .settings,
            onProgress: onProgress,
        )
    }
}

enum WhereCoreTestSupport {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static func calendar(timeZone: TimeZone = pacific) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
    }
}

/// A hand-advanced, thread-safe clock for tests that inject a `now` closure
/// (e.g. `WhereServices`, `DataIssueScanner`, `WidgetSnapshotPublisher`): read
/// `now` from the closure while the test drives time forward with `advance(by:)`.
/// Shared so the per-suite copies don't drift.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current += interval }
    }
}

/// Deterministic durable-location sidecar shared by controller/service lifecycle tests.
actor ScriptedLocationOutbox: LocationOutbox {
    enum Failure: Error {
        case load
        case clear
    }

    private var entries: [LocationOutboxEntry]
    private var failsToLoad: Bool
    private var failsToClear: Bool

    init(
        _ samples: [LocationSample] = [],
        failsToLoad: Bool = false,
        failsToClear: Bool = false,
    ) {
        entries = samples.map { LocationOutboxEntry(sample: $0, dataEpochID: .initial) }
        self.failsToLoad = failsToLoad
        self.failsToClear = failsToClear
    }

    func load() async throws -> [LocationOutboxEntry] {
        guard !failsToLoad else { throw Failure.load }
        return entries
    }

    func save(_ entries: [LocationOutboxEntry]) async throws {
        self.entries = entries
    }

    func clear() async throws {
        guard !failsToClear else { throw Failure.clear }
        entries.removeAll()
    }

    func setFailsToClear(_ value: Bool) {
        failsToClear = value
    }

    func setFailsToLoad(_ value: Bool) {
        failsToLoad = value
    }

    var persistedSamples: [LocationSample] {
        entries.map(\.sample)
    }
}
