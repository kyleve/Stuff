import Foundation
import Testing

struct PrivacyManifestTests {
    @Test func builtAppContainsTheUserDefaultsRequiredReason() throws {
        let builtProductsPath = try #require(
            ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"],
        )
        let manifestURL = URL(filePath: builtProductsPath)
            .appending(path: "Throw.app")
            .appending(path: "PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            format: nil,
        )
        let manifest = try #require(propertyList as? [String: Any])
        let accessedAPITypes = try #require(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
        )
        let userDefaultsDeclaration = try #require(accessedAPITypes.first { declaration in
            declaration["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults"
        })

        #expect(accessedAPITypes.count == 1)
        #expect(
            userDefaultsDeclaration["NSPrivacyAccessedAPITypeReasons"] as? [String]
                == ["CA92.1"],
        )
    }
}
