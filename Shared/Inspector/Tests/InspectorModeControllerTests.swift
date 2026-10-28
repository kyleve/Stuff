import Foundation
@testable import Inspector
import Testing

@MainActor
struct InspectorModeControllerTests {
    @Test func latchesAndClearsTheNextLaunchSelection() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.cleanup() }

        let controller = InspectorModeController(userDefaults: fixture.defaults)
        #expect(controller.nextLaunch == .regularApplication)

        controller.enterInspectorOnNextLaunch()
        #expect(controller.nextLaunch == .inspector)
        #expect(
            InspectorModeController(userDefaults: fixture.defaults).nextLaunch
                == .inspector,
        )

        controller.useRegularApplicationOnNextLaunch()
        #expect(controller.nextLaunch == .regularApplication)
        #expect(
            InspectorModeController(userDefaults: fixture.defaults).nextLaunch
                == .regularApplication,
        )
    }

    @Test func dedicatedSuiteDoesNotTouchInspectedApplicationDefaults() throws {
        let control = try DefaultsFixture(prefix: "inspector.control")
        let application = try DefaultsFixture(prefix: "inspector.application")
        defer {
            control.cleanup()
            application.cleanup()
        }
        application.defaults.set("kept", forKey: "application-value")

        let controller = InspectorModeController(userDefaults: control.defaults)
        controller.enterInspectorOnNextLaunch()
        application.defaults.removePersistentDomain(forName: application.suiteName)

        #expect(controller.nextLaunch == .inspector)
        #expect(control.defaults.bool(forKey: "inspector.nextLaunch.enabled"))
        #expect(application.defaults.object(forKey: "application-value") == nil)
    }

    @Test func nextProcessRepeatsScheduledStoreCleanupBeforeOpeningIt() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.cleanup() }
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-pending-erase-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storeURL = rootURL.appending(path: "Periscope.store")
        let shmURL = rootURL.appending(path: "Periscope.store-shm")
        let recoveryURL = rootURL.appending(
            path: "Periscope-Journals",
            directoryHint: .isDirectory,
        )
        try Data("store".utf8).write(to: storeURL)
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true,
        )
        let controller = InspectorModeController(userDefaults: fixture.defaults)
        try controller.scheduleStoreFamilyErasure(
            storeURL: storeURL,
            storageRootURL: rootURL,
            recoveryStorageURLs: [recoveryURL],
        )

        try InspectorSwiftDataStoreFamily(
            storeURL: storeURL,
            storageRootURL: rootURL,
            recoveryStorageURLs: [recoveryURL],
        ).erase(using: .default)
        // Simulate a failed store coordinator recreating a sidecar after the
        // in-session verification completed.
        try Data("late checkpoint".utf8).write(to: shmURL)
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true,
        )
        try Data("late journal".utf8).write(to: recoveryURL.appending(path: "segment"))

        let nextProcessController = InspectorModeController(userDefaults: fixture.defaults)
        #expect(nextProcessController.completePendingStoreErasures(fileManager: .default))
        #expect(
            FileManager.default.fileExists(atPath: shmURL.path(percentEncoded: false)) == false,
        )
        #expect(
            FileManager.default.fileExists(
                atPath: recoveryURL.path(percentEncoded: false),
            ) == false,
        )
        #expect(nextProcessController.pendingStoreErasureError == nil)
    }

    @Test func failedBootCleanupStaysLatchedAndObservable() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.cleanup() }
        let storageRootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-pending-root-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let outsideRootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-pending-outside-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(
            at: storageRootURL,
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: outsideRootURL,
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: storageRootURL) }
        defer { try? FileManager.default.removeItem(at: outsideRootURL) }
        let storeURL = outsideRootURL.appending(path: "Periscope.store")
        try Data("store".utf8).write(to: storeURL)
        let controller = InspectorModeController(userDefaults: fixture.defaults)
        try controller.scheduleStoreFamilyErasure(
            storeURL: storeURL,
            storageRootURL: storageRootURL,
            recoveryStorageURLs: [],
        )

        #expect(controller.completePendingStoreErasures(fileManager: .default) == false)
        #expect(controller.pendingStoreErasureError?.contains("outside") == true)
        #expect(
            FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)),
        )

        let nextProcessController = InspectorModeController(userDefaults: fixture.defaults)
        #expect(nextProcessController.completePendingStoreErasures(fileManager: .default) == false)
    }

    @Test func pendingCleanupFromAnOlderInspectorBuildStillDecodes() throws {
        struct LegacyPendingStoreErasure: Codable {
            let storeURL: URL
            let storageRootURL: URL

            private enum CodingKeys: String, CodingKey {
                case storeURL = "store_url"
                case storageRootURL = "storage_root_url"
            }
        }

        let fixture = try DefaultsFixture()
        defer { fixture.cleanup() }
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-legacy-pending-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storeURL = rootURL.appending(path: "Periscope.store")
        try Data("store".utf8).write(to: storeURL)
        try fixture.defaults.set(
            JSONEncoder().encode([
                LegacyPendingStoreErasure(
                    storeURL: storeURL,
                    storageRootURL: rootURL,
                ),
            ]),
            forKey: "inspector.pendingStoreErasures",
        )

        let controller = InspectorModeController(userDefaults: fixture.defaults)
        #expect(controller.completePendingStoreErasures(fileManager: .default))
        #expect(
            FileManager.default.fileExists(
                atPath: storeURL.path(percentEncoded: false),
            ) == false,
        )
    }
}

private struct DefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    init(prefix: String = "inspector.mode") throws {
        suiteName = "\(prefix).\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
