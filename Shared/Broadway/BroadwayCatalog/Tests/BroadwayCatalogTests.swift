import Testing
@testable import BroadwayCatalog

@Suite("BroadwayCatalog Tests")
struct BroadwayCatalogTests {
    @Test("App launches with ContentView")
    func contentViewExists() {
        let view = ContentView()
        #expect(view != nil)
    }
}
