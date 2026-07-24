import Foundation
import PortholeCore
@_spi(Testing) import PortholeKit
import Testing

private struct FakePermissionsReader: PermissionsReading {
    let values: [PermissionStatus]
    func statuses() async -> [PermissionStatus] {
        values
    }
}

struct PermissionsConnectorTests {
    @Test func mapsEveryStatusToARow() async throws {
        let reader = FakePermissionsReader(values: [
            PermissionStatus(permission: "notifications", status: "authorized"),
            PermissionStatus(permission: "location", status: "denied"),
            PermissionStatus(permission: "camera", status: "notDetermined"),
        ])
        let connector = PermissionsConnector(reader: reader)
        let source = try #require(connector.dataSources()
            .first { $0.descriptor.id == "permissions" })
        let page = try await source.fetch(PortholeQuery())

        #expect(page.rows.count == 3)
        let byName = Dictionary(uniqueKeysWithValues: page.rows.compactMap { row -> (
            String,
            String
        )? in
            guard let name = row["permission"]?.stringValue,
                  let status = row["status"]?.stringValue else { return nil }
            return (name, status)
        })
        #expect(byName["notifications"] == "authorized")
        #expect(byName["location"] == "denied")
        #expect(byName["camera"] == "notDetermined")
    }

    @Test func systemReaderReturnsAllKnownPermissionsWithoutPrompting() async {
        // The production reader must return a row for each known permission and
        // never prompt (all reads are status queries).
        let statuses = await SystemPermissionsReader().statuses()
        let names = Set(statuses.map(\.permission))
        #expect(names.isSuperset(of: [
            "notifications",
            "location",
            "camera",
            "microphone",
            "photos",
        ]))
    }
}
