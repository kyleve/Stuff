import Foundation
import SwiftUI
import Testing
import ViewDocumentUI
@testable import WhereUI

struct WhereThemeTintAdjustmentTests {
    @Test func explicitZeroLeavesRuntimeRegionTintUnchanged() throws {
        let value = WhereThemeTintAdjustment(
            color: .constant(.rgba(red: 0, green: 0, blue: 0, alpha: 1)),
            fraction: 0,
        )
        #expect(try JSONDecoder().decode(
            WhereThemeTintAdjustment.self,
            from: JSONEncoder().encode(value),
        ) == value)
        let resolved = try value.resolve(
            mode: .light,
            appearance: .init(background: .white, dimensionScales: [:]),
            base: .unchanged,
        )
        #expect(resolved.apply(to: .orange) == .orange)
    }
}
