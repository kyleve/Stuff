@testable import DisplayProbe
import Testing
import UIKit

struct ScreenPointsPerInchTests {
    @Test @MainActor func invokesTheInstalledRuntimeGetter() throws {
        let scene = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let reading = ScreenPointsPerInch.read(from: scene.screen)
        guard case let .available(value) = reading else {
            Issue.record("Expected _pointsPerInch on this runtime; got \(reading.description)")
            return
        }
        #expect(value.isFinite)
        #expect(value > 0)
    }

    @Test func unavailableReadingsDoNotLookLikeMeasuredZero() {
        #expect(ScreenPointsPerInch.unavailable.description == "Unavailable")
        #expect(ScreenPointsPerInch.incompatibleSignature
            .description == "Unavailable · incompatible SPI signature")
        #expect(ScreenPointsPerInch.invalidValue.description == "Unavailable · invalid SPI value")
    }
}
