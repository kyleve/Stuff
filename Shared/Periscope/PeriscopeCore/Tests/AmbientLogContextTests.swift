import Foundation
import PeriscopeCore
import Testing

struct AmbientLogContextTests {
    let sink = CapturingSink()
    let system: Periscope

    init() {
        system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
    }

    @Test func currentFallsBackToASharedRootLogger() {
        let current = Log<AppLogs>.current
        #expect(current.primaryScope.name == "AppLogs")
        #expect(current.primaryScope.parentID == nil)
    }

    @Test func withContextMakesTheLoggerAmbient() async {
        let log = Log<AppLogs>(system: system)

        await log.withContext {
            Log<FreeformLogScope>.current.info("deep")
        }
        await system.flush()

        #expect(sink.records.map(\.message) == ["deep"])
        #expect(sink.records.first?.scopes == log.scopes.map(\.id))
    }

    @Test func currentCanBeTypedToAnyEvent() async {
        let log = Log<AppLogs>(system: system)

        await log.withContext {
            Log<PhotoLogs>.current.event(photoID: .restricted(.identifier, "p1"))
        }
        await system.flush()

        #expect(sink.records.map(\.message) == ["photo p1"])
        #expect(sink.records.first?.scopes == log.scopes.map(\.id))
    }

    @Test func nestedContextsLinkWithTheInnerLogPrimary() async {
        let model = Log<PhotoLogs>(system: system)
        let ui = Log<AppLogs>(system: system)

        await model.withContext {
            await ui.withContext {
                Log<FreeformLogScope>.current.info("both")
            }
        }
        await system.flush()

        let expected = (ui.scopes + model.scopes).map(\.id)
        #expect(sink.records.first?.scopes == expected)
    }

    @Test func nestingTheSameContextTwiceCollapsesDuplicates() async {
        let log = Log<AppLogs>(system: system)

        await log.withContext {
            await log.withContext {
                Log<FreeformLogScope>.current.info("once")
            }
        }
        await system.flush()

        #expect(sink.records.first?.scopes == log.scopes.map(\.id))
    }

    @Test func contextPropagatesIntoStructuredChildTasks() async {
        let log = Log<AppLogs>(system: system)

        await log.withContext {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    Log<FreeformLogScope>.current.info("from child task")
                }
                await group.waitForAll()
            }
        }
        await system.flush()

        #expect(sink.records.map(\.message) == ["from child task"])
        #expect(sink.records.first?.scopes == log.scopes.map(\.id))
    }

    @Test func synchronousWithContextBindsTheContextToo() async {
        let log = Log<AppLogs>(system: system)

        log.withContext {
            Log<FreeformLogScope>.current.info("sync")
        }
        await system.flush()

        #expect(sink.records.map(\.message) == ["sync"])
        #expect(sink.records.first?.scopes == log.scopes.map(\.id))
    }

    @Test func ambientTagsStampEventsLoggedThroughCurrent() async {
        let key = LogTagKey("payment-id")
        let log = Log<AppLogs>(system: system).tagged(key, "pay_123")

        await log.withContext {
            Log<FreeformLogScope>.current.info("tagged")
        }
        await system.flush()

        #expect(sink.records.first?.tags == [LogTag(key: key, value: "pay_123")])
    }

    @Test func nestedContextTagsMergeWithTheInnerWinning() async {
        let key = LogTagKey("payment-id")
        let outer = Log<AppLogs>(system: system).tagged(key, "outer")
        let inner = Log<PhotoLogs>(system: system)
            .tagged(key, "inner")
            .tagged(LogTagKey("extra"), "e")

        await outer.withContext {
            await inner.withContext {
                Log<FreeformLogScope>.current.info("both")
            }
        }
        await system.flush()

        #expect(sink.records.first?.tags == [
            LogTag(key: key, value: "inner"),
            LogTag(key: LogTagKey("extra"), value: "e"),
        ])
    }

    @Test func contextEndsWhenWithContextReturns() async {
        let log = Log<AppLogs>(system: system)
        await log.withContext {}

        let after = Log<AppLogs>.current
        #expect(after.primaryScope == LogScope.root(named: "AppLogs"))
    }

    @Test func withContextReturnsTheBodyValue() async {
        let log = Log<AppLogs>(system: system)
        let value = await log.withContext { 42 }
        #expect(value == 42)
    }
}
