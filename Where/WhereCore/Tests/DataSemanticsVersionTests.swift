import Testing
@testable import WhereCore

struct DataSemanticsVersionTests {
    @Test func comparesComponentsWithoutCollapsingThePolicyVersion() {
        let base = DataSemanticsVersion(major: 1, minor: 2, patch: 3)
        #expect(base < DataSemanticsVersion(major: 1, minor: 2, patch: 4))
        #expect(base < DataSemanticsVersion(major: 1, minor: 3, patch: 0))
        #expect(base < DataSemanticsVersion(major: 2, minor: 0, patch: 0))
        #expect(base == DataSemanticsVersion(major: 1, minor: 2, patch: 3))
    }
}
