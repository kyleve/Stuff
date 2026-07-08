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
}
