import PeriscopeCore
@testable import PeriscopeTools
import Testing

/// Covers the exit-mode label the chips and the viewer's exit filter show.
struct SpanExitDisplayTests {
    @Test func namesTheModeForChipsAndFilters() {
        #expect(SpanExit.Mode.success.displayName == "Success")
        #expect(SpanExit.Mode.superseded.displayName == "Superseded")
    }

    /// Every mode has to be nameable — the filter lists all of them, so a mode
    /// added without a label would render as an unpickable blank row.
    @Test func namesEveryMode() {
        #expect(SpanExit.Mode.allCases.allSatisfy { !$0.displayName.isEmpty })
    }
}
