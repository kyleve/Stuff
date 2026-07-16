import Foundation
import WhereCore

/// Thrown by `TestStore.setManualDay` when failure injection is enabled.
struct ManualSaveFailure: Error, Equatable {}

/// Thrown by `TestStore.samples(in:)` when failure injection is enabled, so a
/// year-report load can be forced to fail.
struct SampleReadFailure: Error, Equatable {}

/// Test `WhereStore` that forwards to an in-memory `SwiftDataStore` but adds
/// two hooks the view-model tests need:
///
/// - `enableFirstSamplesGate()` suspends the first `samples(in:)` call until
///   the test releases it, so two `refresh()`es can be forced to complete out
///   of order (the stale-year race).
/// - `failManualDays()` makes `setManualDay` throw, so manual-entry error
///   handling is exercisable without a real persistence fault.
///
/// Everything else forwards to the backing store so reads stay deterministic.
actor TestStore: WhereStore {
    private let backing: SwiftDataStore

    private var gateFirstSamplesCall = false
    private var firstSamplesSeen = false
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    private var shouldFailManualDay = false
    private var shouldFailSamples = false

    init() throws {
        backing = try SwiftDataStore.inMemory()
    }

    // MARK: - Test controls

    func enableFirstSamplesGate() {
        gateFirstSamplesCall = true
    }

    /// Suspends until the gated first `samples(in:)` call has arrived.
    func awaitFirstSamplesCall() async {
        guard !firstSamplesSeen else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func releaseFirstSamplesCall() {
        gate?.resume()
        gate = nil
    }

    func failManualDays() {
        shouldFailManualDay = true
    }

    /// Makes `samples(in:)` throw, so a `refresh()`'s year-report load fails and
    /// the model's `.failed` load state is exercisable.
    func failSamples() {
        shouldFailSamples = true
    }

    // MARK: - WhereStore

    func perform<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try await backing.perform(block)
    }

    nonisolated func changes() -> AsyncStream<Void> {
        backing.changes()
    }

    func add(sample: LocationSample) async throws {
        try await backing.add(sample: sample)
    }

    func samples(in interval: DateInterval) async throws -> [LocationSample] {
        if shouldFailSamples { throw SampleReadFailure() }
        if gateFirstSamplesCall, !firstSamplesSeen {
            firstSamplesSeen = true
            arrival?.resume()
            arrival = nil
            await withCheckedContinuation { gate = $0 }
        }
        return try await backing.samples(in: interval)
    }

    func allSamples() async throws -> [LocationSample] {
        try await backing.allSamples()
    }

    func write(evidence: Evidence, blob: Data?) async throws {
        try await backing.write(evidence: evidence, blob: blob)
    }

    func evidence(in interval: DateInterval) async throws -> [Evidence] {
        try await backing.evidence(in: interval)
    }

    func allEvidence() async throws -> [Evidence] {
        try await backing.allEvidence()
    }

    func evidenceBlob(for id: UUID) async throws -> Data? {
        try await backing.evidenceBlob(for: id)
    }

    func setManualDay(_ day: DayPresence) async throws {
        if shouldFailManualDay { throw ManualSaveFailure() }
        try await backing.setManualDay(day)
    }

    func clearManualDay(_ day: CalendarDay) async throws {
        try await backing.clearManualDay(day)
    }

    func manualDays(in dayRange: ClosedRange<CalendarDay>) async throws -> [DayPresence] {
        try await backing.manualDays(in: dayRange)
    }

    func allManualDays() async throws -> [DayPresence] {
        try await backing.allManualDays()
    }

    func clear(
        in interval: DateInterval,
        manualDays dayRange: ClosedRange<CalendarDay>,
    ) async throws {
        try await backing.clear(in: interval, manualDays: dayRange)
    }

    func clearAll() async throws {
        try await backing.clearAll()
    }

    func dismissedIssueIDs() async throws -> Set<DataIssueID> {
        try await backing.dismissedIssueIDs()
    }

    func allDismissedIssues() async throws -> [DismissedIssue] {
        try await backing.allDismissedIssues()
    }

    func setIssueDismissed(_ dismissed: Bool, id: DataIssueID) async throws {
        try await backing.setIssueDismissed(dismissed, id: id)
    }

    func restoreDismissedIssue(_ issue: DismissedIssue) async throws {
        try await backing.restoreDismissedIssue(issue)
    }
}
