import Foundation
import Testing
import WhereSurface

struct WhereSurfaceDocumentTests {
    @Test func oldWidgetDocumentDecodesWithoutGlanceFields() throws {
        let data = Data(
            """
            {
              "day": 0,
              "year": 2026,
              "dayRegions": ["us-CA"],
              "totals": ["us-CA", 1]
            }
            """.utf8,
        )

        let document = try JSONDecoder().decode(WhereSurfaceDocument.self, from: data)

        #expect(document.generatedAt == nil)
        #expect(document.surface == nil)
    }

    @Test func widgetOnlyKeysAreIgnored() throws {
        let region = WhereSurfaceSnapshot.Region(
            id: "us-CA",
            name: "California",
            emoji: nil,
            symbolName: nil,
        )
        let surface = WhereSurfaceSnapshot(
            day: Date(timeIntervalSinceReferenceDate: 10),
            todayRegions: [region],
            year: 2026,
            yearToDate: [.init(region: region, days: 42)],
        )
        let encoder = JSONEncoder()
        let document = WhereSurfaceDocument(
            generatedAt: Date(timeIntervalSinceReferenceDate: 20),
            surface: surface,
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(document)) as? [String: Any],
        )
        object["dayRegions"] = ["us-NY"]
        object["totals"] = ["us-NY": 9]
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WhereSurfaceDocument.self, from: data)

        #expect(decoded == document)
    }
}
