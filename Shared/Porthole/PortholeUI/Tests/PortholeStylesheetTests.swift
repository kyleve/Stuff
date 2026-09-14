@testable import PortholeUI
import SwiftUI
import Testing
#if canImport(UIKit)
    import BroadwayCore
    import UIKit
#endif

struct PortholeStylesheetTests {
    @Test func defaultsKeepCodeAndRowsReadable() {
        #expect(PortholeStylesheet.default.row.spacing > 0)
        #expect(PortholeStylesheet.default.row.padding > 0)
        #expect(PortholeStylesheet.default.code.minimumHeight >= 180)
    }

    #if canImport(UIKit)
        @MainActor @Test func resolvesAccessibilityGeometryThroughBroadway() throws {
            var context = BContext(traits: .system)
            context.traitOverrides.contentSizeCategory = .accessibilityLarge
            let resolved = try context.stylesheets.get(PortholeStylesheet.self)
            #expect(resolved.row.spacing == 12)
            #expect(resolved.code.minimumHeight == 240)
            #expect(EnvironmentValues().portholeStylesheet.row == PortholeStylesheet.default.row)
        }
    #endif
}
