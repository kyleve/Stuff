import Foundation
@_spi(Testing) import PeriscopeCore
import PortholeRuntime
import Testing
@testable import WhereUI

struct WherePortholeSystemCapabilitiesTests {
    @Test func logPagesExcludeLaterAppendsAndReturnCopiedEvidence() async throws {
        let store = try await PeriscopeStore.inMemory(session: .current(attributes: [:]))
        let root = LogScope.root(named: "porthole-log-query")
        await store.defineScopes([root])
        await store.write((0 ..< 5).map { index in
            LogRecord(
                date: Date(timeIntervalSince1970: Double(index)),
                event: WherePortholeQueryEvent(message: "event-\(index)"),
                scopes: [root.id],
            )
        })
        let first = try await WherePortholeSystemCapabilities.queryLogs(
            store: store,
            arguments: arguments(offset: 0, watermark: .null),
        )
        let watermark = try #require(first["throughSequence"])
        #expect(first["nextOffset"] == .integer(2))
        #expect(try rows(first).compactMap { $0["message"]?.stringValue } == [
            "event-4",
            "event-3",
        ])
        await store.write([
            LogRecord(
                date: Date(timeIntervalSince1970: 100),
                event: WherePortholeQueryEvent(message: "later"),
                scopes: [root.id],
            ),
        ])
        let second = try await WherePortholeSystemCapabilities.queryLogs(
            store: store,
            arguments: arguments(offset: 2, watermark: watermark),
        )
        #expect(try rows(second).compactMap { $0["message"]?.stringValue } == [
            "event-2",
            "event-1",
        ])
        let last = try await WherePortholeSystemCapabilities.queryLogs(
            store: store,
            arguments: arguments(offset: 4, watermark: watermark),
        )
        #expect(try rows(last).count == 1)
        #expect(last["nextOffset"] == .null)
        #expect(try !String(decoding: JSONEncoder().encode(first), as: UTF8.self)
            .contains("$reference"))
        #expect(try rows(first).allSatisfy { $0["value"] == nil })
    }

    @Test(arguments: [-1, Int64.max])
    func rejectsInvalidOffsets(offset: Int64) async throws {
        let store = try await PeriscopeStore.inMemory(session: .current(attributes: [:]))
        await #expect(throws: PortholeError.self) {
            try await WherePortholeSystemCapabilities.queryLogs(
                store: store,
                arguments: arguments(offset: offset, watermark: .null),
            )
        }
    }

    private func rows(_ value: PortholeValue) throws -> [PortholeValue] {
        guard case let .array(rows) = value["events"] else {
            throw PortholeError.invalidArguments("The log response has no event rows")
        }
        return rows
    }

    private func arguments(offset: Int64, watermark: PortholeValue) -> PortholeValue {
        .object([
            "contains": .string(""),
            "externalID": .null,
            "afterSequence": .null,
            "throughSequence": watermark,
            "offset": .integer(offset),
            "limit": .integer(2),
        ])
    }
}

private struct WherePortholeQueryEvent: LogEvent {
    let message: String
}
