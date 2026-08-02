import Foundation
import Testing
import UIKit
import WhereCore
@testable import WhereUI

@MainActor
struct CurrentRecordingDeviceProviderTests {
    private static let vendorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private static let restoredID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    @Test func mapsInterfaceIdiomsToRecordingKinds() {
        #expect(CurrentRecordingDeviceProvider.kind(for: .phone) == .phone)
        #expect(CurrentRecordingDeviceProvider.kind(for: .pad) == .tablet)
        #expect(CurrentRecordingDeviceProvider.kind(for: .mac) == .other)
    }

    @Test func persistsOneDeviceLocalInstallationIdentity() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let first = try current(fixture: fixture, vendorID: Self.vendorID)
        let second = try current(fixture: fixture, vendorID: Self.vendorID)

        #expect(first == second)
        #expect(first.id.rawValue == Self.vendorID)
        #expect(first.systemName == "iPhone")
        #expect(
            try fixture.identityFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true,
        )
    }

    @Test func migratesAUserDefaultThatMatchesThisDevice() throws {
        let fixture = try makeFixture(legacyID: Self.vendorID)
        defer { fixture.cleanup() }

        let current = try current(fixture: fixture, vendorID: Self.vendorID)

        #expect(current.id.rawValue == Self.vendorID)
        #expect(fixture.defaults.string(forKey: "where.recordingDeviceID") == nil)
    }

    @Test func rejectsARestoredUserDefaultFromAnotherDevice() throws {
        let fixture = try makeFixture(legacyID: Self.restoredID)
        defer { fixture.cleanup() }

        let current = try current(fixture: fixture, vendorID: Self.vendorID)

        #expect(current.id.rawValue == Self.vendorID)
        #expect(current.id.rawValue != Self.restoredID)
    }

    @Test func preUnlockFallbackRemainsStableAfterUnlock() throws {
        let fixture = try makeFixture(legacyID: Self.restoredID)
        defer { fixture.cleanup() }

        let beforeUnlock = try current(fixture: fixture, vendorID: nil)
        let afterUnlock = try current(fixture: fixture, vendorID: Self.vendorID)

        #expect(beforeUnlock == afterUnlock)
        #expect(beforeUnlock.id.rawValue != Self.restoredID)
    }

    private func current(
        fixture: Fixture,
        vendorID: UUID?,
    ) throws -> CurrentRecordingDevice {
        try CurrentRecordingDeviceProvider.current(
            identityFileURL: fixture.identityFileURL,
            legacyDefaults: fixture.defaults,
            vendorID: vendorID,
            systemName: "iPhone",
            kind: .phone,
        )
    }

    private func makeFixture(legacyID: UUID? = nil) throws -> Fixture {
        let suiteName = "CurrentRecordingDeviceProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        if let legacyID {
            defaults.set(legacyID.uuidString, forKey: "where.recordingDeviceID")
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: suiteName, directoryHint: .isDirectory)
        return Fixture(
            directory: directory,
            identityFileURL: directory.appending(path: "recording-device-id"),
            defaults: defaults,
            suiteName: suiteName,
        )
    }

    private struct Fixture {
        let directory: URL
        let identityFileURL: URL
        let defaults: UserDefaults
        let suiteName: String

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
