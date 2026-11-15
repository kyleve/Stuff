import BroadwayUI
import SwiftUI
import Testing

@MainActor
struct BSurfaceTests {
    @Test func onlyNativeContentDeterminesLayout() throws {
        let view = BSurface(shape: Rectangle(), finish: EmptyModifier()) {
            Color.white
        } interior: {
            Color.red.frame(width: 1000, height: 1000)
        } content: {
            Color.clear.frame(width: 80, height: 60)
        } highlights: {
            Rectangle().stroke(.black, lineWidth: 1)
        } exterior: {
            Color.blue.frame(width: 1000, height: 1000)
        }
        let image = try #require(ImageRenderer(content: view).uiImage)
        #expect(image.size == CGSize(width: 80, height: 60))
    }
}
