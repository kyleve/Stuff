import Foundation
import SwiftUI
import Testing
@testable import WhereUI

struct WhereThemeAnimationTests {
    @Test func finiteTimingRoundTripsAndRejectsInvalidDuration() throws {
        let value = WhereThemeAnimation.spring(duration: 0.4, bounce: 0.2)
        #expect(try JSONDecoder().decode(
            WhereThemeAnimation.self,
            from: JSONEncoder().encode(value),
        ) == value)
        #expect(value.animation == Animation.spring(duration: 0.4, bounce: 0.2))
        #expect(throws: WhereThemeValidationError.self) { try WhereThemeValidation.validate(
            .easeOut(duration: 100),
            path: "animation",
        ) }
    }
}
