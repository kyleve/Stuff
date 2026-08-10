import Testing
@testable import Where
import WhereCore

struct WhereBuildEnvironmentTests {
    private let infoDictionary: [String: Any] = [
        "WhereAudience": "development",
        "WhereAppGroupIdentifier": "group.com.stuff.where.development",
        "WherePrimaryAppIconName": "AppIconDevelopment",
    ]

    @Test func developmentBuildInjectsItsIsolatedStorageAndIcon() {
        let environment = WhereBuildEnvironment.current(
            infoDictionary: infoDictionary,
            processEnvironment: [:],
        )

        #expect(environment.audience == .development)
        #expect(environment.appGroupIdentifier == "group.com.stuff.where.development")
        #expect(environment.primaryAppIconName == "AppIconDevelopment")
        #expect(environment.storage == .localOnly(
            appGroupIdentifier: "group.com.stuff.where.development",
        ))
    }

    @Test func hostedTestsAlwaysReceiveInMemoryStorage() {
        let environment = WhereBuildEnvironment.current(
            infoDictionary: infoDictionary,
            processEnvironment: ["XCTestConfigurationFilePath": "/tmp/WhereTests.xctest"],
        )

        #expect(environment.storage == .inMemory)
    }

    @Test func cloudKitValidationBuildUsesTheDevelopmentAppGroup() {
        let environment = WhereBuildEnvironment.current(
            infoDictionary: infoDictionary,
            processEnvironment: [:],
        )

        #expect(environment.storage(forCloudKitValidationBuild: true) == .cloudKit(
            appGroupIdentifier: "group.com.stuff.where.development",
        ))
    }
}
