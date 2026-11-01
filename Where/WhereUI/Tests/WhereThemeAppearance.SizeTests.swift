import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeSizePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"size":{"statusIconWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.size.statusIconWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"size":{"launchIcon":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.size.launchIcon,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"size":{"launchCaptionBottomInset":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.size.launchCaptionBottomInset,
            replacement: 42,
        )
    }
}
