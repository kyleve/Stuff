import Foundation
@testable import PortholeCore
import Testing

struct PortholeValueTests {
    @Test func scalarsRoundTrip() throws {
        #expect(try wireRoundTrip(.null) == .null)
        #expect(try wireRoundTrip(.bool(true)) == .bool(true))
        #expect(try wireRoundTrip(.bool(false)) == .bool(false))
        #expect(try wireRoundTrip(.int(42)) == .int(42))
        #expect(try wireRoundTrip(.int(-7)) == .int(-7))
        #expect(try wireRoundTrip(.double(1.5)) == .double(1.5))
        #expect(try wireRoundTrip(.string("hi")) == .string("hi"))
    }

    @Test func dataRoundTripsAsTaggedObject() throws {
        let value = PortholeValue.data(Data([0x00, 0x01, 0xFF, 0x10]))
        #expect(try wireRoundTrip(value) == value)

        let shape = try jsonObject(value)
        #expect(shape.count == 1)
        #expect(shape["$data"] as? String == Data([0x00, 0x01, 0xFF, 0x10]).base64EncodedString())
    }

    @Test func dateRoundTripsAtMillisecondPrecision() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let value = PortholeValue.date(date)
        let restored = try wireRoundTrip(value)
        let restoredDate = try #require(restored.dateValue)
        #expect(abs(restoredDate.timeIntervalSince1970 - date.timeIntervalSince1970) < 0.001)

        let shape = try jsonObject(value)
        #expect(shape.count == 1)
        #expect(shape["$date"] is String)
    }

    @Test func nestedContainersRoundTrip() throws {
        let value = PortholeValue.object([
            "name": "Where",
            "count": 3,
            "ratio": 0.25,
            "tags": .array(["a", "b"]),
            "nested": .object(["flag": true, "empty": .null]),
        ])
        #expect(try wireRoundTrip(value) == value)
    }

    @Test func integerAccessorAcceptsWholeDouble() {
        #expect(PortholeValue.int(5).intValue == 5)
        #expect(PortholeValue.double(5.0).intValue == 5)
        #expect(PortholeValue.double(5.5).intValue == nil)
        #expect(PortholeValue.string("5").intValue == nil)
    }

    @Test func accessorsAndSubscripts() {
        let value: PortholeValue = ["items": .array([1, 2, 3]), "label": "hi"]
        #expect(value["label"]?.stringValue == "hi")
        #expect(value["items"]?[1]?.intValue == 2)
        #expect(value["missing"] == nil)
        #expect(value["items"]?[9] == nil)
        #expect(value.objectValue?.count == 2)
    }

    @Test func literalConformances() {
        let value: PortholeValue = [
            "n": nil,
            "b": true,
            "i": 7,
            "d": 1.5,
            "s": "x",
            "arr": [1, 2],
        ]
        #expect(value["n"] == .null)
        #expect(value["b"] == .bool(true))
        #expect(value["i"] == .int(7))
        #expect(value["d"] == .double(1.5))
        #expect(value["s"] == .string("x"))
        #expect(value["arr"] == .array([.int(1), .int(2)]))
    }
}
