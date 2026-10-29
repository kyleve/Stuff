import BroadwayCore
import Foundation
import Testing

struct BThemeValueTests {
    @Test func roundTripsAndResolvesExplicitMode() throws {
        let values: [BThemeValue<Double>] = [.constant(0), .modes(.init(light: 1, dark: 2))]
        let decoded = try JSONDecoder().decode(
            [BThemeValue<Double>].self,
            from: JSONEncoder().encode(values),
        )
        #expect(decoded == values)
        #expect(decoded[0].resolve(mode: .dark) == 0)
        #expect(decoded[1].resolve(mode: .light) == 1)
        #expect(decoded[1].resolve(mode: .dark) == 2)
    }
}
