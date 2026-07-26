import SwiftUI
import Testing
@testable import WhereUI

/// Covers `DayCountMorph`'s two halves staying in step: Reduce Motion picks the
/// crossfade, and each case pulls its own animation off the stylesheet rather
/// than sharing one curve.
struct DayCountMorphTests {
    private let motion = WhereStylesheet.default.motion

    @Test func rollsTheDigitsWithFullMotion() {
        #expect(DayCountMorph(reduceMotion: false) == .numericRoll)
    }

    @Test func crossfadesUnderReduceMotion() {
        #expect(DayCountMorph(reduceMotion: true) == .crossfade)
    }

    @Test func theRollUsesTheDayCountAnimation() {
        #expect(DayCountMorph.numericRoll.animation(motion) == motion.dayCountChange)
    }

    @Test func theCrossfadeUsesTheReducedAnimation() {
        #expect(DayCountMorph.crossfade.animation(motion) == motion.reducedDayCountChange)
    }

    @Test func theTwoCasesAnimateDifferently() {
        #expect(
            DayCountMorph.numericRoll.animation(motion)
                != DayCountMorph.crossfade.animation(motion),
        )
    }
}
