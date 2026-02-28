import Testing
@testable import BroadwayUI

@Suite("BroadwayUI Tests")
struct BroadwayUITests {
    @Test("BroadwayUI module is importable")
    func moduleExists() {
        // Verifies the framework builds and is importable.
        #expect(true)
    }
}
