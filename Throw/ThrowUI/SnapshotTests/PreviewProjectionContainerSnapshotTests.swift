import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct PreviewProjectionContainerSnapshotTests {
    @Test func previewProjectionContainer() async {
        await assertSnapshots(of: PreviewProjectionContainer.self)
    }
}
