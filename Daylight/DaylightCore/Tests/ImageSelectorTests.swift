@testable import DaylightCore
import Foundation
import Testing

struct ImageSelectorTests {
    @Test func selectionIgnoresUtilitiesAndBreaksTiesByEventDistance() throws {
        let event = SolarEvent(
            id: .init(year: 2026, month: 6, day: 21, kind: .sunrise),
            date: Date(timeIntervalSince1970: 10000),
        )
        var sequence = CaptureSequence(event: event, settings: .standard)
        for index in [0, 6, 12] {
            var image = CapturedImage(
                id: sequence.slots[index].id,
                capturedAt: sequence.slots[index].scheduledAt,
                recipe: .original,
            )
            image.score = .scored(.init(overall: index == 12 ? 1 : 0.5, isUtility: index == 12))
            sequence.slots[index].state = .captured(image)
        }
        #expect(try ImageSelector().select(from: sequence).id == sequence.slots[6].id)
    }

    @Test func noSuccessfulScoresThrows() {
        let event = SolarEvent(id: .init(year: 2026, month: 6, day: 21, kind: .sunset), date: .now)
        #expect(throws: DaylightError.self) {
            try ImageSelector().select(from: CaptureSequence(event: event, settings: .standard))
        }
    }
}
