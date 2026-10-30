import Foundation
import Testing
@testable import WhereUI

struct WhereThemeContentLayoutTests {
    @Test func wireLayoutResolvesNativePolicy() throws {
        let value = try JSONDecoder().decode(
            WhereThemeAppearance.ContentLayout.self,
            from: Data(#"{"stacked":{}}"#.utf8),
        )
        #expect(value.native == .stacked)
    }
}
