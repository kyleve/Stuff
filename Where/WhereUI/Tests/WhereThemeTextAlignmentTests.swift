import Foundation
import SwiftUI
import Testing
@testable import WhereUI

struct WhereThemeTextAlignmentTests {
    @Test func wireAlignmentResolvesNativeRole() throws {
        let value = try JSONDecoder().decode(
            WhereThemeTextAlignment.self,
            from: Data(#""trailing""#.utf8),
        )
        #expect(value.alignment == .trailing)
    }
}
