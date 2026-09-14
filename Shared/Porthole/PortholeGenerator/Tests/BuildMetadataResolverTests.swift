@testable import PortholeGenerator
import Testing

struct BuildMetadataResolverTests {
    @Test func usesExplicitBuildIdentityWithoutLaunchingAnotherCompiler() throws {
        let build = try BuildMetadataResolver.resolve(environment: [
            "PORTHOLE_BUILD_CONFIGURATION": "Beta",
            "CONFIGURATION": "Debug",
            "PORTHOLE_TOOLCHAIN_ID": "Apple Swift exact-version",
        ]) {
            Issue.record("The explicit toolchain must avoid another compiler lookup")
            return "unexpected"
        }
        #expect(build.configuration == "Beta")
        #expect(build.toolchain == "Apple Swift exact-version")
    }

    @Test func readsTheCompilerVersionInsteadOfTheLanguageMode() throws {
        let build = try BuildMetadataResolver.resolve(environment: [
            "SWIFT_VERSION": "6",
            "CONFIGURATION": "Release",
        ]) { "Apple Swift observed-version" }
        #expect(build.configuration == "Release")
        #expect(build.toolchain == "Apple Swift observed-version")
    }

    @Test func missingConfigurationStaysUnknownAndCompilerFailureRemainsVisible() throws {
        let build = try BuildMetadataResolver
            .resolve(environment: [:]) { "Apple Swift observed-version" }
        #expect(build.configuration == "unknown")
        #expect(throws: GeneratorError.self) {
            try BuildMetadataResolver
                .resolve(environment: [:]) { throw GeneratorError.arguments("Compiler unavailable")
                }
        }
    }
}
