import Foundation
@_spi(Testing) import PeriscopeCore
import PortholeCore
import PortholeKit
import PortholePeriscope
import Testing

private struct AppLogs: LogEvent {
    static let eventName = "AppLogs"
    var level: LogLevel = .info
    var message: String = ""
}

struct PeriscopeConnectorTests {
    private func makeStore() async throws -> (PeriscopeStore, LogScope) {
        let session = LogSession(
            id: UUID(),
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            appVersion: "1.0",
            buildNumber: "1",
            osVersion: "TestOS",
            deviceModel: "Test",
        )
        let store = try await PeriscopeStore.inMemory(session: session)
        let root = LogScope.root(named: "app")
        await store.defineScopes([root])
        return (store, root)
    }

    private func source(
        _ connector: PeriscopeConnector,
        _ id: PortholeDataSourceID,
    ) -> PortholeDataSource {
        connector.dataSources().first { $0.descriptor.id == id }!
    }

    private func connector(_ store: PeriscopeStore) -> PeriscopeConnector {
        PeriscopeConnector(
            store: store,
            system: Periscope(configuration: Periscope.Configuration(), sinks: []),
        )
    }

    @Test func eventsSourceReturnsRowsNewestFirst() async throws {
        let (store, root) = try await makeStore()
        await store.write([
            LogRecord(
                date: Date(timeIntervalSinceReferenceDate: 1),
                event: Message(level: .info, "first"),
                scopes: [root.id],
            ),
            LogRecord(
                date: Date(timeIntervalSinceReferenceDate: 2),
                event: Message(level: .warning, "second"),
                scopes: [root.id],
            ),
        ])
        let page = try await source(connector(store), "events").fetch(PortholeQuery())
        #expect(page.rows.compactMap { $0["message"]?.stringValue } == ["second", "first"])
        #expect(page.rows.first?["level"]?.stringValue == "warning")
        #expect(page.rows.first?["sequence"]?.intValue != nil)
    }

    @Test func minimumLevelFilters() async throws {
        let (store, root) = try await makeStore()
        await store.write([
            LogRecord(
                date: Date(timeIntervalSinceReferenceDate: 1),
                event: Message(level: .info, "info"),
                scopes: [root.id],
            ),
            LogRecord(
                date: Date(timeIntervalSinceReferenceDate: 2),
                event: Message(level: .error, "error"),
                scopes: [root.id],
            ),
        ])
        let page = try await source(connector(store), "events")
            .fetch(PortholeQuery(filters: ["minimumLevel": "warning"]))
        #expect(page.rows.compactMap { $0["message"]?.stringValue } == ["error"])
    }

    @Test func messageContainsFilters() async throws {
        let (store, root) = try await makeStore()
        await store.write([
            LogRecord(
                date: Date(timeIntervalSinceReferenceDate: 1),
                event: Message(level: .info, "load started"),
                scopes: [root.id],
            ),
            LogRecord(
                date: Date(timeIntervalSinceReferenceDate: 2),
                event: Message(level: .info, "save done"),
                scopes: [root.id],
            ),
        ])
        let page = try await source(connector(store), "events")
            .fetch(PortholeQuery(filters: ["messageContains": "load"]))
        #expect(page.rows.compactMap { $0["message"]?.stringValue } == ["load started"])
    }

    @Test func scopesSourceListsHierarchy() async throws {
        let (store, root) = try await makeStore()
        let child = root.child(named: "network")
        await store.defineScopes([child])
        let page = try await source(connector(store), "scopes").fetch(PortholeQuery())
        let names = Set(page.rows.compactMap { $0["name"]?.stringValue })
        #expect(names.contains("app"))
        #expect(names.contains("network"))
    }

    @Test func liveEventsStreamsEmittedRecords() async throws {
        let (store, _) = try await makeStore()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        let connector = PeriscopeConnector(store: store, system: system)
        let subscribe = try #require(source(connector, "live-events").subscribe)
        let stream = subscribe()

        let emitter = Task {
            let log = Log<AppLogs>(system: system)
            while !Task.isCancelled {
                log.info("tick")
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { emitter.cancel() }

        let first = try await withTimeout {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        #expect(first?["message"]?.stringValue == "tick")
    }
}

private struct PeriscopeTimeout: Error {}

private func withTimeout<T: Sendable>(
    _ duration: Duration = .seconds(3),
    _ operation: @escaping @Sendable () async -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw PeriscopeTimeout()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
