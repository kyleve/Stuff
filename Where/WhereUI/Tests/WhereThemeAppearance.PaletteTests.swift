import Foundation
import SwiftUI
import Testing
@testable import WhereUI

@MainActor
struct WhereThemePalettePatchTests {
    @Test func overridesColorWithoutReplacingSiblingPalette() throws {
        try verifyThemePatch(
            json: #"{"palette":{"primary":{"backgroundTop":{"constant":{"_0":{"rgba":{"red":1,"green":0,"blue":0,"alpha":1}}}}}}}"#,
            keyPath: \WhereStylesheet.palette.primary.backgroundTop,
            replacement: Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1),
        )
    }
}
