import Foundation
import Testing
@testable import WhereCore

struct WhereThemeTests {
    @Test func rawValuesAreStable() {
        #expect(WhereTheme.standard.rawValue == "standard")
        #expect(WhereTheme.alternate.rawValue == "alternate")
    }

    @Test(arguments: WhereTheme.allCases)
    func codableRoundTrip(theme: WhereTheme) throws {
        let data = try JSONEncoder().encode(theme)
        #expect(try JSONDecoder().decode(WhereTheme.self, from: data) == theme)
    }
}
