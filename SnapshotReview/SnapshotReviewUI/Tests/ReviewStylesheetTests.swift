import BroadwayCore
import BroadwayUI
@testable import SnapshotReviewUI
import SwiftUI
import Testing

struct ReviewStylesheetTests {
    @MainActor @Test(arguments: [DynamicTypeSize.large, .accessibility1])
    func resolvesAccessibilityGeometryFromTheEnvironment(size: DynamicTypeSize) throws {
        var context = BContext(traits: .system)
        context.traitOverrides.contentSizeCategory = .init(size)
        let sheet = try context.stylesheets.get(ReviewStylesheet.self)
        #expect(sheet.browser.sidebarWidth == (size.isAccessibilitySize ? 400 : 320))
        #expect(sheet.canvas.pinSize == (size.isAccessibilitySize ? 40 : 28))
        var environment = EnvironmentValues()
        environment.bContext = context
        #expect(environment.reviewStyle == sheet)
    }

    @Test func sidebarAndGridHaveUsableDefaults() {
        #expect(ReviewStylesheet.default.browser.sidebarWidth >= 260)
        #expect(ReviewStylesheet.default.browser.cellWidth >= 200)
        #expect(ReviewStylesheet.default.canvas.pinSize >= 28)
    }
}
