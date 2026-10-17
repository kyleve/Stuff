@testable import Flagger
import Testing

struct JSONValueTests {
    @Test
    func roundTripsNestedJSON() throws {
        let value = JSONValue.object([
            "enabled": .boolean(true),
            "rollout": .number(0.25),
            "groups": .array([.string("staff"), .null]),
        ])

        #expect(try JSONValue(formatted: value.formatted) == value)
    }

    @Test
    func preservesLargeIntegerPrecision() throws {
        let integer = Int64.max
        let json = try FlagDefinition.json(integer)

        #expect(try FlagDefinition.value(Int64.self, from: json) == integer)
    }
}
