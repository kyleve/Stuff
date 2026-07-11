import BroadwayCore
import BroadwayUI
import SwiftUI
import Testing

@MainActor
struct BContextEnvironmentTests {
    private enum ProbeTheme: String, BTheme {
        static let defaultValue: Self = .a
        case a, b
    }

    @Test("A SwiftUI-set context takes precedence and reads back synchronously")
    func swiftUISetContextWins() {
        var context = BContext(traits: .system)
        context.themes[ProbeTheme.self] = .b

        var env = EnvironmentValues()
        env.bContext = context

        #expect(env.bContext == context)
        #expect(env.bContext.themes[ProbeTheme.self] == .b)
    }

    @Test("bContext falls back to the default when no SwiftUI context is set")
    func fallsBackToDefault() {
        #expect(EnvironmentValues().bContext == BContextTrait.defaultValue)
    }

    @Test("Transforming bContext (as bTraitOverrides does) round-trips via the SwiftUI value")
    func transformRoundTrips() {
        var env = EnvironmentValues()
        var context = env.bContext
        context.traitOverrides.mode = .dark
        env.bContext = context

        #expect(env.bContext.traits.mode == .dark)
    }
}
