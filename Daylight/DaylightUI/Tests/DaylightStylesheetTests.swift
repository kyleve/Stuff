import BroadwayCore
import BroadwayUI
@testable import DaylightUI
import SwiftUI
import TestHostSupport
import Testing

@MainActor
struct DaylightStylesheetTests {
    @Test func defaultGeometryIsUsable() {
        #expect(DaylightStylesheet.default.preview.aspectRatio > 1)
        #expect(DaylightStylesheet.default.capture.padding >= 16)
    }
}
