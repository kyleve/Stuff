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
            "gold",
            "lime",
            "coral",
            "magenta",
            "silver",
            "slate",
            "charcoal",
        ])
    }

    @Test func regionSymbolRawValuesAreStable() {
        #expect(RegionSymbol.allCases.map(\.rawValue) == [
            "mappin.circle.fill",
            "location.fill",
            "map.fill",
            "flag.fill",
            "house.fill",
            "building.2",
            "building.2.fill",
            "building.columns.fill",
            "tent.fill",
            "sun.max",
            "sun.max.fill",
            "moon.stars.fill",
            "cloud.fill",
            "snowflake",
            "leaf.fill",
            "tree.fill",
            "mountain.2.fill",
            "water.waves",
            "airplane",
            "car.fill",
            "tram.fill",
            "sailboat.fill",
            "star.fill",
            "heart.fill",
            "flame.fill",
            "bolt.fill",
            "globe.americas.fill",
            "beach.umbrella.fill",
            "camera.fill",
            "sparkles",
            "location.magnifyingglass",
        ])
    }

    @Test func appearanceCodableRoundTrips() throws {
        let appearance = RegionAppearance(color: .teal, emoji: "🌴", symbolName: .sunMaxFill)
        let data = try JSONEncoder().encode(appearance)
        #expect(String(decoding: data, as: UTF8.self).contains("\"symbolName\":\"sun.max.fill\""))
        let decoded = try JSONDecoder().decode(RegionAppearance.self, from: data)
        #expect(decoded == appearance)
    }

    @Test func appearanceRejectsAnUnknownPersistedSymbol() {
        let data = Data(#"{"color":"teal","emoji":"🌴","symbolName":"not.a.symbol"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RegionAppearance.self, from: data)
        }
    }
}
