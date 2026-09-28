@testable import DaylightCore
import Foundation
import Testing

struct CapturedImageTests {
    @Test func readsCaptureFromBeforeRAWAndDeliveryCheckpoints() throws {
        let data = Data(
            #"{"id":{"rawValue":"00000000-0000-0000-0000-000000000001"},"capturedAt":1000,"photos":{"saved":{"_0":"existing-asset"}},"score":{"pending":{}},"recipe":{"preset":"original"}}"#
                .utf8,
        )
        let image = try JSONDecoder().decode(CapturedImage.self, from: data)
        #expect(image.format == nil)
        #expect(image.capturedEventHandled == nil)
        #expect(image.photos == .saved("existing-asset"))
    }

    @Test func retainsRAWFormatAndCompletedDeliveryCheckpoint() throws {
        var image = CapturedImage(
            id: .init(rawValue: UUID()),
            capturedAt: Date(),
            format: .rawAndJPEG,
        )
        image.capturedEventHandled = true
        let decoded = try JSONDecoder().decode(
            CapturedImage.self,
            from: JSONEncoder().encode(image),
        )
        #expect(decoded == image)
    }
}
