@testable import BroadwayCore
import Testing

@MainActor
struct BContextStylesheetConvenienceTests {
    private enum ModeTheme: String, BTheme {
        static let defaultValue: Self = .light
        case light, dark

        var mode: BMode {
            self == .dark ? .dark : .light
        }
    }

    private struct ValueSheet: BStylesheet {
        var mode: BMode

        init(context: SlicingContext) {
            mode = context.themes[ModeTheme.self].mode
        }

        init(mode: BMode) {
            self.mode = mode
        }
    }

    @Test("stylesheet(_:fallback:) returns the resolved sheet on success")
    func resolvesSuccessfully() {
        var themes = BThemes()
        themes[ModeTheme.self] = .dark
        let context = BContext(traits: .system, themes: themes)

        let sheet = context.stylesheet(ValueSheet.self, fallback: ValueSheet(mode: .light))

        #expect(sheet.mode == .dark)
    }

    @Test("stylesheet(_:fallback:) caches through the context resolver")
    func resolvesThroughTheCache() {
        let context = BContext(traits: .system)

        let first = context.stylesheet(ValueSheet.self, fallback: ValueSheet(mode: .dark))
        let second = context.stylesheet(ValueSheet.self, fallback: ValueSheet(mode: .dark))

        // Default theme resolves to `.light`; the fallback (`.dark`) is never used.
        #expect(first.mode == .light)
        #expect(second == first)
    }
}
