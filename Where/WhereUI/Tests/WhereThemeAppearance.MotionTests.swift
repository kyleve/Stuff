import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeMotionPatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"motion":{"staggeredReveal":{"verticalOffset":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.motion.staggeredReveal.verticalOffset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"motion":{"staggeredReveal":{"delay":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.motion.staggeredReveal.delay,
            replacement: 42,
        )
    }
}
