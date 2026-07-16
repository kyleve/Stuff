import Foundation
import Testing
import WhereCore

struct WhereStoreURLCodableTests {
    // MARK: - StoreURL builder / parser

    @Test func url_sortsQueryItemsForStableOutput() {
        let url = StoreURL.url(
            collection: "issues",
            type: "abruptChange",
            items: ["later": "2026-04-02", "earlier": "2026-04-01"],
        )
        // Keys are emitted sorted, so the same identity is always the same string.
        #expect(
            url.absoluteString == "store://issues/abruptChange?earlier=2026-04-01&later=2026-04-02",
        )
    }

    @Test func parts_roundTripsBuiltURL() throws {
        let url = StoreURL.url(
            collection: "issues",
            type: "borderDrift",
            items: ["day": "2026-04-01"],
        )
        let parts = try #require(StoreURL.parts(of: url))
        #expect(parts.collection == "issues")
        #expect(parts.type == "borderDrift")
        #expect(parts.value("day") == "2026-04-01")
        #expect(parts.value("missing") == nil)
    }

    @Test func parts_rejectsNonStoreURLs() throws {
        #expect(try StoreURL.parts(of: #require(URL(string: "https://issues/borderDrift"))) == nil)
        #expect(try StoreURL.parts(of: #require(URL(string: "store://issues"))) == nil)
    }

    // MARK: - DataIssueID conformance

    @Test func dataIssueID_codableRoundTripsAsBareURLString() throws {
        let ids: [DataIssueID] = [
            .missingDays(start: CalendarDay(year: 2026, month: 1, day: 5)),
            .borderDrift(day: CalendarDay(year: 2026, month: 4, day: 1)),
            .abruptChange(
                earlier: CalendarDay(year: 2026, month: 4, day: 1),
                later: CalendarDay(year: 2026, month: 4, day: 2),
            ),
        ]
        for id in ids {
            let data = try JSONEncoder().encode(id)
            // Encodes as a single bare URL string, not a keyed object.
            let asString = try JSONDecoder().decode(String.self, from: data)
            #expect(asString == id.storeURL.absoluteString)
            #expect(try JSONDecoder().decode(DataIssueID.self, from: data) == id)
        }
    }

    @Test func dataIssueID_rejectsMalformedStoreURLs() throws {
        let bad = [
            "store://other/borderDrift?day=2026-04-01", // wrong collection
            "store://issues/unknownType?day=2026-04-01", // unknown type
            "store://issues/borderDrift", // missing day param
            "store://issues/borderDrift?day=2026-13-99", // impossible date
            "https://issues/borderDrift?day=2026-04-01", // wrong scheme
        ]
        for string in bad {
            let url = try #require(URL(string: string))
            #expect(DataIssueID(storeURL: url) == nil)
        }
    }

    @Test func dataIssueID_decodeThrowsOnMalformedURL() {
        let json = Data(#""store://issues/borderDrift""#.utf8) // missing day param
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DataIssueID.self, from: json)
        }
    }
}
