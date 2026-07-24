import Foundation
@testable import PortholeCLICore
import PortholeCore
import Testing

struct OutputFormattingTests {
    @Test func jsonRendersObjectWithSortedKeys() throws {
        let value: PortholeValue = ["b": 2, "a": 1]
        let json = OutputFormatting.json(value)
        // Sorted keys put "a" before "b".
        let aIndex = try #require(json.range(of: "\"a\""))
        let bIndex = try #require(json.range(of: "\"b\""))
        #expect(aIndex.lowerBound < bIndex.lowerBound)
    }

    @Test func jsonRendersScalarFragments() {
        #expect(OutputFormatting.json(.int(42)) == "42")
        #expect(OutputFormatting.json(.string("hi")) == "\"hi\"")
    }

    @Test func jsonRendersDataAsTaggedMarker() {
        let value = PortholeValue.data(Data([0x01, 0x02]))
        let json = OutputFormatting.json(value)
        #expect(json.contains("$data"))
        #expect(json.contains(Data([0x01, 0x02]).base64EncodedString()))
    }

    @Test func tableAlignsColumnsAcrossRows() {
        let rows: [PortholeValue] = [
            ["id": "a", "count": 1],
            ["id": "bb", "count": 22],
        ]
        let table = OutputFormatting.table(rows)
        let lines = table.split(separator: "\n").map(String.init)
        #expect(lines.count == 4) // header, divider, 2 rows
        // The header contains both columns (sorted: count, id).
        #expect(lines[0].contains("count"))
        #expect(lines[0].contains("id"))
    }

    @Test func tableHandlesEmptyRows() {
        #expect(OutputFormatting.table([]) == "(no rows)")
    }

    @Test func cellStringSummarizesData() {
        #expect(OutputFormatting.cellString(.data(Data(count: 5))) == "<5 bytes>")
        #expect(OutputFormatting.cellString(.bool(true)) == "true")
        #expect(OutputFormatting.cellString(nil) == "")
    }
}
