import Foundation
import SwiftUI
import Testing
@testable import WhereUI

struct WhereThemeBlendTests {
    @Test func preservesLuminosityWireRole() throws {
        let value = try JSONDecoder().decode(
            WhereThemeBlend.self,
            from: Data(#""luminosity""#.utf8),
        )
        #expect(value.blendMode == .luminosity)
        #expect(try JSONEncoder().encode(value) == Data(#""luminosity""#.utf8))
    }
}
