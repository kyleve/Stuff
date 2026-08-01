import Foundation
import Testing
import WhereSurface

struct WhereSurfaceFileCoordinatorTests {
    @Test func missingFileReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "missing.json")

        let data = try WhereSurfaceFileCoordinator().read(from: fileURL)

        #expect(data == nil)
    }

    @Test func writeThenReadRoundTrips() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "snapshot.json")
        let expected = Data("coordinated".utf8)
        let coordinator = WhereSurfaceFileCoordinator()

        try coordinator.write(expected, to: fileURL)

        #expect(try coordinator.read(from: fileURL) == expected)
    }

    @Test func writeReplacesExistingContents() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "snapshot.json")
        let coordinator = WhereSurfaceFileCoordinator()
        try coordinator.write(Data("old".utf8), to: fileURL)
        let replacement = Data("new".utf8)

        try coordinator.write(replacement, to: fileURL)

        #expect(try coordinator.read(from: fileURL) == replacement)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WhereSurfaceFileCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
