@testable import Flagger
import Testing

struct FlagDefinitionTests {
    @Test
    func erasesAndRestoresTheConcreteValueType() throws {
        let definition = try TestFlags().liveBoolean.definition(
            propertyName: "liveBoolean",
            source: FeatureFlagSourceMetadata(id: TestFlagSource.id, name: TestFlagSource.name),
            group: FeatureFlagGroupMetadata(id: TestFlags.id, name: TestFlags.name, detail: nil),
        )

        #expect(definition.propertyName == "liveBoolean")
        #expect(definition.defaultValue == .boolean(false))
        #expect(try definition.decode(.boolean(true)) as? Bool == true)
    }
}
