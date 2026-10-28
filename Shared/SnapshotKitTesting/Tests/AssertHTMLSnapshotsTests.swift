@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct AssertHTMLSnapshotsTests {
    @Test func rejectsFixedAndAccessibilityCaptures() async {
        for configuration in [
            SnapshotConfiguration(device: .iPhone),
            SnapshotConfiguration(device: .iPhoneFullContent, snapshotType: .accessibility),
        ] {
            await #expect(throws: (any Error).self) {
                try await loadHTMLSnapshotImage("<p>Fixture</p>", configuration: configuration)
            }
        }
    }

    @Test func cancelledCaptureDoesNotLoadWebKit() async {
        let task = Task {
            try await loadHTMLSnapshotImage(
                "<p>Fixture</p>",
                configuration: .init(device: .iPhoneFullContent),
            )
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
