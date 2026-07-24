import Foundation
import PeriscopeCore
import PortholeCore
import PortholeKit

/// A Porthole connector (id `periscope`) exposing the app's Periscope logs: a
/// queryable event history, a live event tail, and the scope tree.
public final class PeriscopeConnector: PortholeConnector {
    public let descriptor = PortholeConnectorDescriptor(
        id: "periscope",
        title: "Periscope",
        summary: "The app's structured logs: query history, tail live events, and browse the scope tree.",
        version: 1,
    )

    private let store: PeriscopeStore
    private let system: Periscope

    private static let levelsByName: [String: LogLevel] = Dictionary(
        uniqueKeysWithValues: LogLevel.standardLevels.map { ($0.name, $0) },
    )

    public init(store: PeriscopeStore, system: Periscope) {
        self.store = store
        self.system = system
    }

    public func dataSources() -> [PortholeDataSource] {
        let store = store
        let system = system
        return [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "events",
                    title: "Events",
                    summary: "Stored log events, newest first. Page with limit + cursor.",
                    rowSchema: eventRowSchema,
                    filters: .object([
                        "minimumLevel": .string(
                            "Minimum level",
                            allowedValues: LogLevel.standardLevels.map(\.name),
                        ),
                        "eventName": .string("Exact event type name"),
                        "messageContains": .string("Substring to match in the message"),
                        "start": .date("Only events at/after this date"),
                        "end": .date("Only events before this date"),
                        "afterSequence": .integer(
                            "Only events with a higher sequence (live cursor)",
                        ),
                    ]),
                    supportsSubscription: false,
                ),
                fetch: { query in
                    let limit = query.limit ?? 100
                    let offset = Int(query.cursor ?? "0") ?? 0
                    let logQuery = Self.logQuery(from: query.filters, limit: limit, offset: offset)
                    let events = try await store.events(matching: logQuery)
                    let rows = events.map(Self.eventRow)
                    return PortholePage(
                        rows: rows,
                        nextCursor: events.count == limit ? String(offset + limit) : nil,
                    )
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "live-events",
                    title: "Live events",
                    summary: "A live stream of log events as they're emitted.",
                    rowSchema: eventRowSchema,
                    filters: .object([:]),
                    supportsSubscription: true,
                ),
                fetch: { _ in PortholePage(rows: []) },
                subscribe: {
                    AsyncStream { continuation in
                        let task = Task {
                            for await record in system.liveRecords() {
                                if Task.isCancelled { break }
                                continuation.yield(Self.liveRow(record))
                            }
                            continuation.finish()
                        }
                        continuation.onTermination = { _ in task.cancel() }
                    }
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "scopes",
                    title: "Scopes",
                    summary: "The log scope hierarchy (id, name, parent).",
                    rowSchema: .object(["id": .string(), "name": .string(), "parentID": .string()]),
                    filters: .object([:]),
                    supportsSubscription: false,
                ),
                fetch: { _ in
                    let scopes = try await store.scopes()
                    let rows = scopes.map { scope -> PortholeValue in
                        var object: [String: PortholeValue] = [
                            "id": .string(scope.id.description),
                            "name": .string(scope.name),
                        ]
                        if let parent = scope
                            .parentID { object["parentID"] = .string(parent.description) }
                        return .object(object)
                    }
                    return PortholePage(rows: rows, totalCount: rows.count)
                },
            ),
        ]
    }

    private var eventRowSchema: PortholeSchema {
        .object([
            "date": .date(),
            "sequence": .integer(),
            "level": .string(),
            "eventName": .string(),
            "message": .string(),
            "scopes": .array(of: .string()),
            "externalID": .string(),
        ])
    }

    private static func logQuery(from filters: PortholeValue, limit: Int, offset: Int) -> LogQuery {
        var query = LogQuery()
        query.limit = limit
        query.offset = offset
        if let level = filters["minimumLevel"]?
            .stringValue { query.minimumLevel = levelsByName[level] }
        if let name = filters["eventName"]?.stringValue { query.eventName = name }
        if let message = filters["messageContains"]?.stringValue { query.messageContains = message }
        if let start = filters["start"]?.dateValue { query.start = start }
        if let end = filters["end"]?.dateValue { query.end = end }
        if let after = filters["afterSequence"]?.intValue { query.afterSequence = Int(after) }
        return query
    }

    private static func eventRow(_ event: StoredLogEvent) -> PortholeValue {
        var object: [String: PortholeValue] = [
            "date": .date(event.date),
            "sequence": .int(Int64(event.sequence)),
            "level": .string(event.level.name),
            "eventName": .string(event.eventName),
            "message": .string(event.message),
            "scopes": .array(event.scopes.map { .string($0.description) }),
        ]
        if let externalID = event.externalID { object["externalID"] = .string(externalID) }
        if !event.tags
            .isEmpty { object["tags"] = .array(event.tags.map { .string(String(describing: $0)) }) }
        if let payload = try? JSONDecoder().decode(PortholeValue.self, from: event.payload) {
            object["payload"] = payload
        }
        return .object(object)
    }

    private static func liveRow(_ record: LogRecord) -> PortholeValue {
        var object: [String: PortholeValue] = [
            "date": .date(record.date),
            "level": .string(record.level.name),
            "eventName": .string(record.eventName),
            "message": .string(record.message),
            "scopes": .array(record.scopes.map { .string($0.description) }),
        ]
        if let externalID = record.externalID { object["externalID"] = .string(externalID) }
        return .object(object)
    }
}
