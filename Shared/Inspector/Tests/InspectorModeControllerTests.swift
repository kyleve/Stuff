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
        try Data("store".utf8).write(to: storeURL)
        let controller = InspectorModeController(userDefaults: fixture.defaults)
        try controller.scheduleStoreFamilyErasure(
            storeURL: storeURL,
            storageRootURL: rootURL,
        )

        try InspectorSwiftDataStoreFamily(
            storeURL: storeURL,
            storageRootURL: rootURL,
        ).erase(using: .default)
        // Simulate a failed store coordinator recreating a sidecar after the
        // in-session verification completed.
        try Data("late checkpoint".utf8).write(to: shmURL)

        let nextProcessController = InspectorModeController(userDefaults: fixture.defaults)
        #expect(nextProcessController.completePendingStoreErasures(fileManager: .default))
        #expect(
            FileManager.default.fileExists(atPath: shmURL.path(percentEncoded: false)) == false,
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
        )

        #expect(controller.completePendingStoreErasures(fileManager: .default) == false)
        #expect(controller.pendingStoreErasureError?.contains("outside") == true)
        #expect(
            FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)),
        )

        let nextProcessController = InspectorModeController(userDefaults: fixture.defaults)
        #expect(nextProcessController.completePendingStoreErasures(fileManager: .default) == false)
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
