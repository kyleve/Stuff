import CreditKit
import Foundation
import Testing

struct SoftwareCreditTests {
    @Test func identifiesByName() {
        #expect(SoftwareCredit.fixture(name: "ZIPFoundation").id == "ZIPFoundation")
    }

    @Test func kindEncodesAsItsWireName() throws {
        // The generator writes these strings, so renaming a case would silently
        // stop matching every report already committed.
        let encoded = try JSONEncoder().encode(SoftwareCredit.Kind.allCases)
        let names = try JSONDecoder().decode([String].self, from: encoded)
        #expect(names == ["library", "developmentTool"])
    }
}
