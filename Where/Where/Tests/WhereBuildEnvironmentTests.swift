import Testing
@testable import Where
import WhereCore

struct WhereBuildEnvironmentTests {
    private let infoDictionary: [String: Any] = [
        "WhereAudience": "development",
        "WhereAppGroupIdentifier": "group.com.stuff.where.development",
        "WherePrimaryAppIconName": "AppIconDevelopment",
        "WhereCloudKitContainerIdentifier": "iCloud.com.stuff.where",
    ]

    @Test func developmentBuildInjectsItsIsolatedStorageAndIcon() {
        let environment = WhereBuildEnvironment.current(
            infoDictionary: infoDictionary,
            processEnvironment: [:],
        )

        #expect(environment.audience == .development)
        #expect(environment.dataset(forCloudKitValidationBuild: false) == .local(
            .init(rawValue: "group.com.stuff.where.development"),
        ))
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
        #expect(environment.dataset(forCloudKitValidationBuild: true) == .local(
            .init(rawValue: "group.com.stuff.where.development"),
        ))
    }

    @Test func cloudKitValidationBuildUsesTheDevelopmentAppGroup() {
        let environment = WhereBuildEnvironment.current(
            infoDictionary: infoDictionary,
            processEnvironment: [:],
        )

        #expect(environment.dataset(forCloudKitValidationBuild: true) == .cloudKit(
            .init(rawValue: "group.com.stuff.where.development"),
            containerIdentifier: "iCloud.com.stuff.where",
        ))
        #expect(environment.storage(forCloudKitValidationBuild: true) == .cloudKit(
            appGroupIdentifier: "group.com.stuff.where.development",
        ))
    }
}
