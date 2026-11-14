import Foundation
import PeriscopeCore
@_spi(Testing) import WhereCore
@testable import WhereUI

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
    init(version: Int) {
        self.version = .init(rawValue: version)
    }

    func setVersion(_ value: Int) {
        version = .init(rawValue: value)
    }

    func accountID() async throws -> DataCompatibilityAccountID {
        .init(rawValue: "launch-test")
    }

    func read(accountID _: DataCompatibilityAccountID) async throws -> SharedDataModelVersion? {
        .init(version: version, revision: String(version.rawValue))
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

    var opens = 0
    var discoveries = 0
    var locationStops = 0
    var stores: [StoreReference] = []
    var source = ScriptedLocationSource()

    func services(context: InstallationRecordingContext) throws -> WhereServices {
        opens += 1
        let store = try SwiftDataStore.inMemory()
        stores.append(StoreReference(store))
        source = ScriptedLocationSource()
        return WhereServices(store: store, locationSource: source, installationContext: context)
    }
}

@MainActor
struct CompatibilityLaunchBootstrap: WhereScopeAssembling {
    let harness: CompatibilityLaunchHarness
    let context: any InstallationRecordingContextStoring
    func prepareLocation() {}
    func stopLocation() async {
        harness.locationStops += 1
    }

    func currentLocationAuthorization() async -> LocationAuthorizationStatus {
        .always
    }

    func requestLocationPermission() async throws {}
    func makeServices() async throws -> WhereServices {
        try harness
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
