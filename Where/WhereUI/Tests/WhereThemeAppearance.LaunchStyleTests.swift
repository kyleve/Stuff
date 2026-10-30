import Testing
@testable import WhereUI

@MainActor
struct WhereThemeLaunchPatchTests {
    @Test func revealOverrideLeavesLifecycleTimingsNative() throws {
        try verifyThemePatch(
            json: #"{"launch":{"reveal":{"constant":{"_0":{"crossfade":{}}}}}}"#,
            keyPath: \WhereStylesheet.launch.reveal,
            replacement: .crossfade,
        )
    }
}
