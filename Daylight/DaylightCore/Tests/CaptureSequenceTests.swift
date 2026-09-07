@testable import DaylightCore
import Foundation
import Testing

struct CaptureSequenceTests {
    @Test func defaultSequenceContainsThirteenSlotsAndFreezesSettings() {
        let event = SolarEvent(
            id: .init(year: 2026, month: 6, day: 21, kind: .sunrise),
            date: Date(timeIntervalSince1970: 10000),
        )
        var settings = CaptureSettings.standard
        let sequence = CaptureSequence(event: event, settings: settings)
        settings.recipe.preset = .warm
        #expect(sequence.slots.count == 13)
        #expect(sequence.slots.first?.scheduledAt == event.date.addingTimeInterval(-1800))
        #expect(sequence.slots.last?.scheduledAt == event.date.addingTimeInterval(1800))
        #expect(Set(sequence.slots.map(\.id)).count == 13)
        #expect(sequence.settings.recipe.preset == .original)
    }
}
