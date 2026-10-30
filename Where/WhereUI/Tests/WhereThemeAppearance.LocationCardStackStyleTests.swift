import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeLocationCardStackStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"locationCardStack":{"overtake":{"duration":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationCardStack.overtake.duration,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationCardStack":{"overtake":{"bounce":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationCardStack.overtake.bounce,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationCardStack":{"overtake":{"lateralArc":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationCardStack.overtake.lateralArc,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationCardStack":{"overtake":{"liftScale":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationCardStack.overtake.liftScale,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationCardStack":{"overtake":{"rotationDegrees":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationCardStack.overtake.rotationDegrees,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationCardStack":{"overtake":{"settleScale":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationCardStack.overtake.settleScale,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationCardStack":{"overtake":{"minimumOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationCardStack.overtake.minimumOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationCardStack":{"overtake":{"usesSpatialMotion":{"constant":{"_0":false}}}}}"#,
            keyPath: \WhereStylesheet.locationCardStack.overtake.usesSpatialMotion,
            replacement: false,
        )
    }
}
