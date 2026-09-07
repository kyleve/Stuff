import Foundation
import Testing
@testable import Where

struct FirstUnlockAvailabilityTests {
    @Test func anAccessibleClassCMarkerAllowsAnOrdinaryLockedLaunch() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("marker")
        try Data([1]).write(
            to: marker,
            options: .completeFileProtectionUntilFirstUserAuthentication,
        )
        let availability = FirstUnlockAvailability(marker: marker, isDeviceUnlocked: { false })
        #expect(await availability.isAvailable())
    }

    @Test(arguments: [true, false])
    func anUnreadableProbeOnlyAllowsAnExplicitlyUnlockedDevice(unlocked: Bool) async throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let availability = FirstUnlockAvailability(
            marker: file.appendingPathComponent("cannot-exist"),
            isDeviceUnlocked: { unlocked },
        )
        #expect(await availability.isAvailable() == unlocked)
    }
}
