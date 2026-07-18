import Foundation
import Testing
@testable import WhereCore

/// `RegionAppearance` / `RegionColorToken` are persisted (the token by
/// `rawValue`), so their raw values and Codable shape must stay stable.
struct RegionAppearanceTests {
    @Test func colorTokenRawValuesAreStable() {
        #expect(RegionColorToken.allCases.map(\.rawValue) == [
            "orange",
            "indigo",
            "red",
            "blue",
            "teal",
            "green",
            "mint",
            "cyan",
            "purple",
            "pink",
            "brown",
        ])
    }

    @Test func appearanceCodableRoundTrips() throws {
        let appearance = RegionAppearance(color: .teal, emoji: "🌴", symbolName: "sun.max.fill")
        let data = try JSONEncoder().encode(appearance)
        let decoded = try JSONDecoder().decode(RegionAppearance.self, from: data)
        #expect(decoded == appearance)
    }
}
