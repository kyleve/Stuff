import Foundation
import PeriscopeCore
import Testing

struct LogTagTests {
    @Test func keyDescribesItsRawValue() {
        #expect(LogTagKey("payment-id").description == "payment-id")
    }

    @Test func keysWithTheSameRawValueAreEqual() {
        #expect(LogTagKey("payment-id") == LogTagKey("payment-id"))
        #expect(LogTagKey("payment-id") != LogTagKey("order-id"))
    }

    @Test func tagRoundTripsThroughCodable() throws {
        let tag = LogTag(key: LogTagKey("payment-id"), value: "pay_123")
        let data = try JSONEncoder().encode(tag)
        let decoded = try JSONDecoder().decode(LogTag.self, from: data)
        #expect(decoded == tag)
    }

    @Test(arguments: [
        LogTagValue.string("pay_123"),
        .int(3),
        .double(0.25),
        .bool(false),
        .encoded(json: #"{"a":1}"#),
    ])
    func typedValuesRoundTripThroughCodable(value: LogTagValue) throws {
        let tag = LogTag(key: LogTagKey("k"), value: value)
        let decoded = try JSONDecoder().decode(LogTag.self, from: JSONEncoder().encode(tag))
        #expect(decoded == tag)
    }

    @Test func literalsConvertToTypedValues() {
        let string: LogTagValue = "pay_1"
        let int: LogTagValue = 3
        let double: LogTagValue = 0.5
        let bool: LogTagValue = true
        #expect(string == .string("pay_1"))
        #expect(int == .int(3))
        #expect(double == .double(0.5))
        #expect(bool == .bool(true))
    }

    @Test func pairsDistinguishValueKinds() {
        // .int(3) and .string("3") share a canonical string; the pair's
        // kind segment keeps them distinct for storage and queries.
        let int = LogTag(key: LogTagKey("k"), value: .int(3))
        let string = LogTag(key: LogTagKey("k"), value: .string("3"))
        #expect(int.value.stringValue == string.value.stringValue)
        #expect(int.pair != string.pair)
    }

    @Test func encodingProducesCanonicalKeySortedJSON() throws {
        struct Payload: Codable {
            var beta: Int
            var alpha: Int
        }
        let value = try LogTagValue.encoding(Payload(beta: 2, alpha: 1))
        #expect(value == .encoded(json: #"{"alpha":1,"beta":2}"#))
    }

    @Test func tagListsLookUpByKey() {
        let key = LogTagKey("payment-id")
        let tags: [LogTag] = [LogTag(key: key, value: "pay_1")]
        #expect(tags[key] == .string("pay_1"))
        #expect(tags[LogTagKey("missing")] == nil)
    }
}
