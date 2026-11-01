import Foundation
import Testing
import WhereCore

struct WidgetPresentationStoreTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "WidgetPresentationStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test(arguments: WhereTheme.allCases)
    func writeThenReadRoundTrips(theme: WhereTheme) throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetPresentationStore(directory: directory)

        try store.write(theme: theme)

        #expect(store.readTheme() == theme)
    }

    @Test func missingOrUnknownPresentationDefaultsToStandard() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetPresentationStore(directory: directory)
        #expect(store.readTheme() == .standard)

        try Data(#""future-theme""#.utf8)
            .write(to: directory.appending(path: "widget-presentation.json"))

        #expect(store.readTheme() == .standard)
    }

    @Test func writeOverwritesThePreviousTheme() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetPresentationStore(directory: directory)

        try store.write(theme: .alternate)
        try store.write(theme: .standard)

        #expect(store.readTheme() == .standard)
    }
}
