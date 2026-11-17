import BroadwayCore
@testable import Flyover
import Testing

struct FlyoverStylesheetTests {
    @MainActor
    @Test func resolvesThroughBroadwayToTheDefaults() throws {
        let context = BContext(traits: .system)
        let resolved = try context.stylesheets.get(FlyoverStylesheet.self)

        #expect(resolved == .default)
    }

    @MainActor
    @Test func removesDecorativeTransparencyWhenReduced() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.accessibility = BAccessibility(
            isReduceTransparencyEnabled: true,
        )
        let resolved = try context.stylesheets.get(FlyoverStylesheet.self)

        #expect(resolved.group.fillOpacity == 1)
        #expect(resolved.screen.shadow.opacity == 0)
    }
}
