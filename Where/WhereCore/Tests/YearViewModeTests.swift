import Testing
@testable import WhereCore

struct YearViewModeTests {
    @Test(arguments: [
        (YearViewMode.calendar, "calendar"),
        (.timeline, "timeline"),
        (.breakdown, "breakdown"),
        (.heatmap, "heatmap"),
    ])
    func rawValuesAreStable(argument: (mode: YearViewMode, rawValue: String)) {
        #expect(argument.mode.rawValue == argument.rawValue)
    }
}
