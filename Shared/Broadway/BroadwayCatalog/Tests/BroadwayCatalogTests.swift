@testable import BroadwayCatalog
import Testing

struct BroadwayCatalogTests {
    @Test("App launches with ContentView")
    func contentViewExists() {
        let view = ContentView()
        #expect(view != nil)
    }
}
