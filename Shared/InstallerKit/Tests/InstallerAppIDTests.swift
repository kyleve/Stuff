import Foundation
import InstallerKit
import Testing

struct InstallerAppIDTests {
    @Test(arguments: [
        "",
        "../where",
        "Where",
        "where/main",
        "where\n",
        String(repeating: "a", count: 65),
    ])
    func rejectsUnsafeOrUnboundedIDs(_ rawValue: String) {
        #expect(InstallerAppID(rawValue: rawValue) == nil)
    }

    @Test func usesASingleStringWireShape() throws {
        let appID = try #require(InstallerAppID(rawValue: "sample-app2"))
        let encoded = try JSONEncoder().encode(appID)
        #expect(String(decoding: encoded, as: UTF8.self) == #""sample-app2""#)
        #expect(try JSONDecoder().decode(InstallerAppID.self, from: encoded) == appID)
    }
}
