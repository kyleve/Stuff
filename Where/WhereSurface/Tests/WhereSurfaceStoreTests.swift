import Foundation
import Testing
import WhereSurface

struct WhereSurfaceStoreTests {
    @Test func missingArtifactReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let document = try WhereSurfaceStore(directory: directory).read()

        #expect(document == nil)
    }

    @Test func readsTheSurfaceOverlayFromWidgetJSON() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = WhereSurfaceDocument(
            generatedAt: Date(timeIntervalSinceReferenceDate: 20),
            surface: WhereSurfaceSnapshot(
                day: Date(timeIntervalSinceReferenceDate: 10),
                todayRegions: [],
                year: 2026,
                yearToDate: [],
            ),
        )
        let data = try JSONEncoder().encode(expected)
        try data.write(
            to: directory.appending(path: WhereSurfaceStore.snapshotFileName),
            options: .atomic,
        )

        let document = try WhereSurfaceStore(directory: directory).read()

        #expect(document == expected)
    }

    @Test func malformedArtifactThrows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(
            to: directory.appending(path: WhereSurfaceStore.snapshotFileName),
        )
        let store = WhereSurfaceStore(directory: directory)

        #expect(throws: DecodingError.self) {
            try store.read()
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WhereSurfaceStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
