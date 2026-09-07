import Testing
import WhereCore
@testable import WhereUI

struct RegionSymbolPresentationTests {
    @Test func everyPersistedSymbolMapsToTheSameSFSymbolName() {
        for symbol in RegionSymbol.allCases {
            #expect(symbol.sfSymbol.rawValue == symbol.rawValue)
        }
    }
}
