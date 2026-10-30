import Foundation
import Testing
@testable import WhereUI

struct WhereThemeOptionalTests {
    @Test func wireFormatDistinguishesClearFromAnExplicitZero() throws {
        let decoder = JSONDecoder()
        #expect(try decoder
            .decode(WhereThemeOptional<Int>.self, from: Data(#"{"clear":{}}"#.utf8)) == .clear)
        #expect(try decoder.decode(
            WhereThemeOptional<Int>.self,
            from: Data(#"{"value":{"_0":0}}"#.utf8),
        ) == .value(0))
    }
}
