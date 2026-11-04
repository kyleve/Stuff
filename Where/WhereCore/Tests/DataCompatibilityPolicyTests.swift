import Testing
@testable import WhereCore

struct DataCompatibilityPolicyTests {
    @Test func incompatibleHeaderRejectsBeforePayloadDecoding() {
        var decoded = false
        #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 2)) {
            try DataCompatibilityTestSupport.policy.decode(authoredWith: .init(
                major: 2,
                minor: 0,
                patch: 0,
            )) {
                decoded = true
            }
        }
        #expect(!decoded)
    }

    @Test func compatibleMinorAndPatchDifferencesNeverGate() throws {
        let value = try DataCompatibilityTestSupport.policy.decode(
            authoredWith: .init(major: 1, minor: 999, patch: 999),
        ) { 42 }
        #expect(value == 42)
    }
}
