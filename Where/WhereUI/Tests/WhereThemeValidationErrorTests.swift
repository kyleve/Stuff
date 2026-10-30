import Testing
@testable import WhereUI

struct WhereThemeValidationErrorTests {
    @Test func diagnosticKeepsFieldPath() {
        let error = WhereThemeValidationError(path: "appearance.card", reason: "Invalid value")
        #expect(error.errorDescription == "appearance.card: Invalid value")
    }
}
