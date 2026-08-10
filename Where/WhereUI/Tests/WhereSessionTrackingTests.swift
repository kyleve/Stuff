import Foundation
import RegionKit
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

/// Covers the launch-time reconciliation that fixes the "toggle is always off"
/// and "Grant does nothing" bugs: tracking and the authorization indicator must
/// reflect real authorization plus the installation-local recording choice,
/// not just the last tap.
@MainActor
struct WhereSessionTrackingTests {
    private func makeSession(
        status: LocationAuthorizationStatus,
        preferences: WherePreferences,
    ) throws -> (WhereSession, ScriptedLocationSource) {
        let (session, source, _) = try makeSessionAndStore(status: status, preferences: preferences)
        return (session, source)
    }

    private func makeSessionAndStore(
        status: LocationAuthorizationStatus,
        preferences: WherePreferences,
        store: SwiftDataStore? = nil,
        installationContext: InstallationRecordingContext = .testing,
        installationContextStore: InMemoryInstallationRecordingContextStore? = nil,
    ) throws -> (WhereSession, ScriptedLocationSource, SwiftDataStore) {
        let store = try store ?? SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: status)
        let resolvedContext = try installationContextStore?.resolve() ?? installationContext
        let services = WhereServices(
            store: store,
            locationSource: source,
            installationContext: resolvedContext,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let contextStore = installationContextStore
            ?? InMemoryInstallationRecordingContextStore(context: resolvedContext)
        let session = WhereSession(
            scope: .fake(services: services, preferences: preferences, logSystem: .shared),
            installationContextStore: contextStore,
        )
        return (session, source, store)
    }

    private func installationContext(
        initialRecordingEnabled: Bool,
    ) -> InstallationRecordingContext {
        guard initialRecordingEnabled == false else { return .testing }
        return InstallationRecordingContext(
            currentDevice: InstallationRecordingContext.testing.currentDevice,
            registeredAt: InstallationRecordingContext.testing.registeredAt,
            recordingChoice: .off,
            isRejoining: false,
        )
    }

    /// A one-shot fix stamped "now", so it lands on today's calendar day
    /// regardless of when the test runs.
    private func todayFix() -> LocationSample {
        LocationSample(
            timestamp: Date(),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }

    @Test func launchWithAlwaysResumesTracking() async throws {
        let (session, _) = try makeSession(status: .always, preferences: makePreferences())
        await session.start()
        #expect(session.authorizationStatus == .always)
        #expect(session.isTracking)
        #expect(!session.permissionDenied)
    }

    @Test func launchWithWhenInUseDoesNotTrack() async throws {
        let (session, _) = try makeSession(status: .whenInUse, preferences: makePreferences())
        await session.start()
        #expect(session.authorizationStatus == .whenInUse)
        #expect(!session.isTracking)
    }

    @Test func launchWithDeniedDoesNotTrackOrAlert() async throws {
        let (session, _) = try makeSession(status: .denied, preferences: makePreferences())
        await session.start()
        #expect(session.authorizationStatus == .denied)
        #expect(!session.isTracking)
        // Launch must not pop the Settings alert; that's reserved for taps.
        #expect(!session.permissionDenied)
    }

    @Test func stoppingTrackingPersistsAcrossLaunches() async throws {
        let preferences = makePreferences()
        let contextStore = InMemoryInstallationRecordingContextStore(context: .testing)
        let (session, _, store) = try makeSessionAndStore(
            status: .always,
            preferences: preferences,
            installationContextStore: contextStore,
        )
        await session.start()
        #expect(session.isTracking)

        await session.stopTracking()
        #expect(!session.isTracking)

        // A fresh session sharing the same store should stay paused even though
        // authorization is still Always.
        let (relaunched, _, _) = try makeSessionAndStore(
            status: .always,
            preferences: preferences,
            store: store,
            installationContextStore: contextStore,
        )
        await relaunched.start()
        #expect(!relaunched.isTracking)
    }

    @Test func offWinsWhileAnEarlierEnableWaitsForPermission() async throws {
        let source = SuspendedPermissionLocationSource()
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
            installationContext: installationContext(initialRecordingEnabled: false),
        )
        let preferences = makePreferences()
        let contextStore = InMemoryInstallationRecordingContextStore(
            context: installationContext(initialRecordingEnabled: false),
        )
        let session = WhereSession(
            scope: .fake(services: services, preferences: preferences, logSystem: .shared),
            installationContextStore: contextStore,
        )
        await session.start()

        let enabling = Task {
            try await session.setRecordingEnabled(true)
        }
        await waitUntil { source.isAwaitingPermission }

        try await session.setRecordingEnabled(false)
        source.resolvePermission(as: .always)
        try await enabling.value

        let current = try #require(
            try await session.recordingDevices()
                .first(where: { $0.id == session.currentRecordingDeviceID }),
        )
        #expect(current.localAutomaticRecordingEnabled == false)
        #expect(current.device.status == .off)
        #expect(session.isTracking == false)
    }

    @Test func grantingLaterStartsTrackingViaLiveUpdates() async throws {
        let (session, source) = try makeSession(
            status: .notDetermined,
            preferences: makePreferences(),
        )
        await session.start()
        #expect(!session.isTracking)

        // Simulate the user granting Always in the system prompt / Settings.
        source.emitAuthorization(.always)

        await waitUntil { session.isTracking }
        #expect(session.authorizationStatus == .always)
        #expect(session.isTracking)
    }

    @Test func remoteRemovalStopsThisDevice() async throws {
        let remoteChanges = ScriptedStoreRemoteChangeSource()
        let store = try SwiftDataStore.inMemory(remoteChangeSource: remoteChanges)
        let source = TrackingLocationSource()
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let services = WhereServices(
            store: store,
            locationSource: source,
            installationContext: .testing,
            now: { now },
        )
        let preferences = makePreferences()
        let session = WhereSession(services: services, preferences: preferences)
        await session.start()

        #expect(session.isTracking)
        #expect(source.isMonitoring)

        let removalID = try RecordingDeviceRemoval.ID(rawValue: #require(
            UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"),
        ))
        try await store.simulateRemoteRecordingImport(
            profiles: [],
            metadataChanges: [],
            checkIns: [],
            removals: [
                RecordingDeviceRemoval(
                    id: removalID,
                    deviceID: InstallationRecordingContext.testing.currentDevice.id,
                    removedAt: now.addingTimeInterval(1),
                    removedByDeviceID: RecordingDeviceID(
                        rawValue: #require(UUID(
                            uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
                        )),
                    ),
                ),
            ],
        )

        // Saving the imported row is not enough; the session must be responding
        // to the store's remote-import notification path.
        #expect(session.isTracking)
        #expect(source.isMonitoring)

        remoteChanges.yield()

        await waitUntil {
            session.isTracking == false && source.isMonitoring == false
        }
        let current = try #require(
            try await store.recordingDevices()
                .first(where: { $0.id == session.currentRecordingDeviceID }),
        )
        #expect(source.startCount == 1)
        #expect(source.stopCount == 1)
        #expect(current.removedAt == now.addingTimeInterval(1))
    }

    @Test func foregroundLogsTodayWhenWantedAndAuthorized() async throws {
        // When-In-Use is enough for a foreground fix — and the only way such a
        // user gets any data, since passive background tracking needs Always.
        let (session, source, store) = try makeSessionAndStore(
            status: .whenInUse,
            preferences: makePreferences(),
        )
        source.setNextRequestedLocation(todayFix())

        await session.appBecameActive()

        await waitUntilAsync { await (try? store.allSamples().count) == 1 }
    }

    @Test func foregroundDoesNotLogTodayWhenTrackingDisabled() async throws {
        let (session, source, store) = try makeSessionAndStore(
            status: .always,
            preferences: makePreferences(),
        )
        // The user turned tracking off; opening the app must not silently log.
        await session.start()
        await session.stopTracking()
        source.setNextRequestedLocation(todayFix())

        await session.appBecameActive()

        // Gating short-circuits before any capture task is spawned.
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func foregroundDoesNotLogTodayWhenUnauthorized() async throws {
        let (session, source, store) = try makeSessionAndStore(
            status: .denied,
            preferences: makePreferences(),
        )
        source.setNextRequestedLocation(todayFix())

        await session.appBecameActive()

        #expect(try await store.allSamples().isEmpty)
    }

    /// Guards against a retain cycle through the long-lived authorization
    /// observer: it captures `[weak self]` and `deinit` cancels it, so dropping
    /// the last strong reference must deallocate the session even while the
    /// observer task is parked awaiting updates.
    @Test func deinitsWhileObservingAuthorization() async throws {
        weak var weakSession: WhereSession?
        do {
            let (session, _) = try makeSession(status: .always, preferences: makePreferences())
            weakSession = session
            // start() spins up the long-lived authorization observer; once it
            // returns the task is parked in `for await` (ScriptedLocationSource
            // emits nothing on its own) holding only a weak self.
            await session.start()
            #expect(weakSession != nil)
        }
        #expect(weakSession == nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: () -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate(), "condition was not met before timeout")
    }

    private func waitUntilAsync(
        timeout: Duration = .seconds(2),
        _ predicate: () async -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await predicate(), "condition was not met before timeout")
    }
}

/// Location source whose counters prove reconciliation reached the physical
/// monitoring seam rather than only changing `WhereSession.isTracking`.
private final class TrackingLocationSource: LocationSource, @unchecked Sendable {
    let sampleStream: AsyncStream<LocationSample>

    var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        AsyncStream { $0.finish() }
    }

    private let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private let lock = NSLock()
    private var _isMonitoring = false
    private var _startCount = 0
    private var _stopCount = 0

    init() {
        (sampleStream, sampleContinuation) = AsyncStream.makeStream(
            of: LocationSample.self,
            bufferingPolicy: .bufferingNewest(1),
        )
    }

    deinit {
        sampleContinuation.finish()
    }

    var isMonitoring: Bool {
        lock.withLock { _isMonitoring }
    }

    var startCount: Int {
        lock.withLock { _startCount }
    }

    var stopCount: Int {
        lock.withLock { _stopCount }
    }

    func start() async {
        lock.withLock {
            _isMonitoring = true
            _startCount += 1
        }
    }

    func stop() async {
        lock.withLock {
            _isMonitoring = false
            _stopCount += 1
        }
    }

    func requestCurrentLocation() async -> LocationSample? {
        nil
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        .always
    }

    func requestPermission() async throws {}
}

/// Permission seam that parks until the test resolves it, matching the
/// suspension point of Core Location's real system prompt.
private final class SuspendedPermissionLocationSource: LocationSource, @unchecked Sendable {
    let sampleStream = AsyncStream<LocationSample> { _ in }

    var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        AsyncStream { _ in }
    }

    private let lock = NSLock()
    private var status = LocationAuthorizationStatus.notDetermined
    private var permissionContinuation: CheckedContinuation<Void, Never>?

    var isAwaitingPermission: Bool {
        lock.withLock { permissionContinuation != nil }
    }

    func start() async {}
    func stop() async {}

    func requestCurrentLocation() async -> LocationSample? {
        nil
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        lock.withLock { status }
    }

    func requestPermission() async throws {
        await withCheckedContinuation { continuation in
            lock.withLock { permissionContinuation = continuation }
        }
    }

    func resolvePermission(as status: LocationAuthorizationStatus) {
        let continuation = lock.withLock {
            self.status = status
            defer { permissionContinuation = nil }
            return permissionContinuation
        }
        continuation?.resume()
    }
}
