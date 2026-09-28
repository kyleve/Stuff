import Foundation
import Testing
@_spi(Testing) @testable import Where

struct FirstUnlockAvailabilityTests {
    @Test(.timeLimit(.minutes(1)))
    func unlockResumesAllLaunchWaitersWithoutReopeningOnOrdinaryRelock() async throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let availability = FirstUnlockAvailability(
            marker: file.appendingPathComponent("inaccessible"),
            isDeviceUnlocked: { false },
        )
        let headless = Task { try await availability.waitUntilAvailable() }
        let foreground = Task { try await availability.waitUntilAvailable() }
        defer { headless.cancel(); foreground.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await availability.waitingCallerCount < 2, ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(await availability.waitingCallerCount == 2)
        await availability.protectedDataDidBecomeAvailable()
        try await headless.value
        try await foreground.value
        #expect(await availability.waitingCallerCount == 0)
        #expect(await availability.isAvailable())
        try await availability.waitUntilAvailable()
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledLaunchWaiterDoesNotOpenOrBlockTheBarrier() async throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let availability = FirstUnlockAvailability(
            marker: file.appendingPathComponent("inaccessible"),
            isDeviceUnlocked: { false },
        )
        let waiter = Task { try await availability.waitUntilAvailable() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await availability.waitingCallerCount == 0, ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(await availability.waitingCallerCount == 1)
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(await availability.waitingCallerCount == 0)
        #expect(await availability.isAvailable() == false)
    }

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
