import BroadwayUI
import Testing
import ViewDocumentCore

struct BArtworkPlacementTests {
    @Test func rejectsUnboundedPaintBeforeHosting() {
        #expect(throws: ViewDocumentValidationError.self) {
            try BArtworkPlacement(.init(
                anchor: .center,
                size: .fixed(width: 80, height: 80),
                offset: .zero,
                plane: .exterior,
                outsets: .init(
                    top: .infinity,
                    leading: 0,
                    bottom: 0,
                    trailing: 0,
                ),
            ))
        }
    }
}
