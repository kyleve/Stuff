import Foundation
import Testing
@testable import WhereCore

struct DataCompatibilityVersionTests {
    @Test func wireValueIsAPositiveInteger() throws {
        let value = DataCompatibilityVersion(rawValue: 2)
        #expect(try JSONEncoder().encode(value) == Data("2".utf8))
        #expect(try JSONDecoder()
            .decode(DataCompatibilityVersion.self, from: Data("2".utf8)) == value)
        #expect(value > .initial)
    }

    @Test(arguments: ["0", "-1", "null", "{}", "1.5"])
    func invalidVersionsFailDecoding(_ input: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DataCompatibilityVersion.self, from: Data(input.utf8))
        }
    }
}
