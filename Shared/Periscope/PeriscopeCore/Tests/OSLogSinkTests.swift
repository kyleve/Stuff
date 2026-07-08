import Foundation
@_spi(Testing) import PeriscopeCore
import Testing

struct OSLogSinkTests {
    let sink = OSLogSink(subsystem: "com.stuff.periscope.tests")

    private func record(primary: LogScope, message: String = "hello") -> LogRecord {
        LogRecord(date: Date(), event: Message(level: .info, message), scopes: [primary.id])
    }

    @Test func categoryIsTheRootScopeName() async {
        let root = LogScope.root(named: "app")
        let photos = root.child(named: "photos")
        let album = photos.child(named: "album-1")
        await sink.defineScopes([root, photos, album])

        #expect(sink.categoryName(for: record(primary: album)) == "app")
        #expect(sink.categoryName(for: record(primary: root)) == "app")
    }

    @Test func messagePrefixesThePathBelowTheRoot() async {
        let root = LogScope.root(named: "app")
        let photos = root.child(named: "photos")
        let album = photos.child(named: "album-1")
        await sink.defineScopes([root, photos, album])

        let deep = sink.formattedMessage(for: record(primary: album))
        #expect(deep == "[photos/album-1] hello")

        let atRoot = sink.formattedMessage(for: record(primary: root))
        #expect(atRoot == "hello")
    }

    @Test func unknownScopesFallBackToAPlainRendering() {
        let unknown = LogScope.root(named: "never-defined")
        #expect(sink.categoryName(for: record(primary: unknown)) == "periscope")
        #expect(sink.formattedMessage(for: record(primary: unknown)) == "hello")
    }

    @Test func writingRecordsIsSafe() async {
        let root = LogScope.root(named: "app")
        await sink.defineScopes([root])
        await sink.write([
            record(primary: root, message: "smoke"),
            LogRecord(
                date: Date(),
                event: Message(level: .fault, "fault smoke"),
                scopes: [root.id],
            ),
        ])
        await sink.flush()
    }
}
