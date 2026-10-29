import BumperBowlingCore
import Testing

/// Mutates the real project graph while retaining its configured rule set.
enum WhereArchitectureTestSupport {
    static func replacing(
        _ component: WhereComponent,
        with replacement: (ComponentConfiguration) -> ComponentConfiguration,
    ) throws -> ArchitectureConfiguration {
        let original = bumper.architecture
        let componentID = try ComponentID(component.rawValue)
        let index = try #require(original.components.firstIndex { $0.name == componentID.rawValue })
        var components = original.components
        components[index] = replacement(components[index])
        return ArchitectureConfiguration(
            includedPaths: original.includedPaths,
            excludedPaths: original.excludedPaths,
            components: components,
            rules: original.rules,
        )
    }
}
