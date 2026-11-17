import Foundation
import LifecycleKit
import PeriscopeCore
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
final class CompatibilityWorkHold {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool {
        continuation != nil
    }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class CompatibilityPollClock {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private(set) var waitCount = 0

    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func wait() async throws {
        waitCount += 1
        for await _ in stream {
            try Task.checkCancellation()
            return
        }
        throw CancellationError()
    }

    func tick() {
        continuation.yield()
    }
}

actor LaunchCompatibilityTransport: DataCompatibilityTransport {
    var version: DataModelVersion
    private var rejectsReads = false
    init(version: Int) {
        self.version = .init(rawValue: version)
    }

    func setVersion(_ value: Int) {
        version = .init(rawValue: value)
    }

    func setRejectsReads(_ value: Bool) {
        rejectsReads = value
    }

    func accountID() async throws -> DataCompatibilityAccountID {
        .init(rawValue: "launch-test")
    }

    func read(accountID _: DataCompatibilityAccountID) async throws -> SharedDataModelVersion? {
        guard !rejectsReads else { throw DataCompatibilityTransportError.invalidRecord }
        return .init(version: version, revision: String(version.rawValue))
    }

    func advance(
        accountID _: DataCompatibilityAccountID,
        from _: SharedDataModelVersion?,
        to version: DataModelVersion,
    ) async throws -> SharedDataModelVersion {
        self.version = max(self.version, version)
        return .init(version: self.version, revision: String(self.version.rawValue))
    }

    nonisolated func accountChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

/// Keeps the recovery drive alive after it publishes ready, including across cancellation.
@MainActor
final class CompatibilityRecoveryHold: LifecycleStep {
    // This teardown ID is unused in the launch plan to which the test appends this step.
    let id = LaunchStepID.suspendCompatibility
    private var runs = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func run(_: WhereSession, _: LifecycleStepContext) async {
        runs += 1
        guard runs == 2 else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class LaunchCompatibilityReceipt: DataCompatibilityReceiptStoring {
    var value: DataCompatibilityReceipt?
    func load() throws -> DataCompatibilityReceipt? {
        value
    }

    func save(_ receipt: DataCompatibilityReceipt) throws {
        value = receipt
    }
}

/// Creates services only when the real launch asks, and retains only weak store references.
@MainActor
final class CompatibilityLaunchHarness {
    final class StoreReference {
        weak var store: SwiftDataStore?
        init(_ store: SwiftDataStore) {
            self.store = store
        }
    }

    var holdNextOpen = false
    private var opening: CheckedContinuation<Void, Never>?
    var isOpening: Bool {
        opening != nil
    }

    func releaseOpen() {
        opening?.resume(); opening = nil
    }

    var opens = 0
    var discoveries = 0
    var initialAuthorization = LocationAuthorizationStatus.always
    var stores: [StoreReference] = []
    var source = CompatibilityLocationSource()

    func makeLocationSource() -> CompatibilityLocationSource {
        source = CompatibilityLocationSource(status: initialAuthorization)
        return source
    }

    func services(context: InstallationRecordingContext) async throws -> WhereServices {
        opens += 1
        let store = try SwiftDataStore.inMemory()
        stores.append(StoreReference(store))
        if holdNextOpen {
            holdNextOpen = false
            await withCheckedContinuation { opening = $0 }
        }
        return WhereServices(store: store, locationSource: source, installationContext: context)
    }
}

@MainActor
struct CompatibilityLaunchBootstrap: WhereScopeAssembling {
    let harness: CompatibilityLaunchHarness
    let context: any InstallationRecordingContextStoring
    func makeServices() async throws -> WhereServices {
        try await harness
            .services(context: context.resolve())
    }

    func discoverRecordingDevices() async throws -> [RecordingDevice] {
        harness.discoveries += 1
        return []
    }

    func makeLogStore() async throws -> PeriscopeStore? {
        nil
    }
}

/// Permission and physical acquisition are observable without using CoreLocation.
@MainActor
final class CompatibilityLocationSource: LocationSource {
    private let scripted: ScriptedLocationSource
    private(set) var stops = 0
    private(set) var permissionRequests = 0

    init(status: LocationAuthorizationStatus = .always) {
        scripted = ScriptedLocationSource(authorizationStatus: status)
    }

    nonisolated var sampleStream: AsyncStream<LocationSample> {
        scripted.sampleStream
    }

    nonisolated var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        scripted.authorizationUpdates
    }

    func start() async {}
    func stop() async {
        stops += 1
    }

    func requestCurrentLocation() async -> CurrentLocationResult {
        await scripted
            .requestCurrentLocation()
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        await scripted
            .currentAuthorization()
    }

    func requestPermission() async throws {
        permissionRequests += 1
        scripted.emitAuthorization(.always)
    }
}
