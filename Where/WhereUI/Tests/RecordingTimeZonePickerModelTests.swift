import Testing
@testable import WhereUI

@MainActor
struct RecordingTimeZonePickerModelTests {
    @Test func searchAcceptsReadableCityNamesAndExactZoneIdentifiers() {
        let model = RecordingTimeZonePickerModel()
        model.search = "  New York  "
        #expect(model.zones.map(\.identifier) == ["America/New_York"])
        model.search = "america/new_york"
        #expect(model.zones.map(\.identifier) == ["America/New_York"])
        model.search = "No Such Recording Zone"
        #expect(model.zones.isEmpty)
        model.search = "   "
        #expect(model.zones.contains { $0.identifier == "America/New_York" })
    }
}
