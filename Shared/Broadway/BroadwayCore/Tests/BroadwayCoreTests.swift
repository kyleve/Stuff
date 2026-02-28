import Testing
@testable import BroadwayCore

@Suite("BroadwayCore Tests")
struct BroadwayCoreTests {
    @Test("BroadwayCore module is importable")
    func moduleExists() {
        #expect(true)
    }
}
