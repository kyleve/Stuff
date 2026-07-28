import Foundation
@testable import PeriscopeCore
import Testing

struct StringCodingKeyTests {
    @Test func carriesTheStringItWasBuiltFrom() {
        #expect(StringCodingKey("thermal").stringValue == "thermal")
        #expect(StringCodingKey(stringValue: "thermal").stringValue == "thermal")
    }

    /// The keys stand in for named string identifiers, so there is no integer
    /// spelling of one — an index-keyed container must not silently resolve to
    /// some position.
    @Test func hasNoIntegerSpelling() {
        #expect(StringCodingKey("thermal").intValue == nil)
        #expect(StringCodingKey(intValue: 0) == nil)
    }
}
