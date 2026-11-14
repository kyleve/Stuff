import Foundation
import Testing
@testable import WhereCore

struct DataModelVersionTests {
    @Test(arguments: [0, -1])
    func invalidWireVersionThrows(value: Int) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DataModelVersion.self, from: Data("\(value)".utf8))
        }
    }

    @Test func wireFormatIsAnInteger() throws {
        let version = DataModelVersion(rawValue: 2)
        #expect(try JSONEncoder().encode(version) == Data("2".utf8))
        #expect(try JSONDecoder().decode(DataModelVersion.self, from: Data("2".utf8)) == version)
    }
}
