import Foundation
import Testing
@testable import WhereCore

struct DataModelVersionTests {
    @Test func baselineHasAnAuthoredReason() throws {
        let reason = try #require(DataModelVersion.baseline.changeReason)
        #expect(reason.localized(preferredLocales: [Locale(identifier: "en")]) ==
            "Where now checks that each device can open your shared data before it syncs.")
    }

    @Test func versionTwoExplainsCanadianSubdivisionVisits() throws {
        let version = DataModelVersion(rawValue: 2)
        #expect(DataModelVersion.current >= version)
        let reason = try #require(version.changeReason)
        #expect(reason.localized(preferredLocales: [Locale(identifier: "en")]) ==
            "Where can now save visits to Canadian provinces and territories.")
    }

    @Test func versionThreeExplainsRecordingAndCorrectionDevices() throws {
        let version = DataModelVersion(rawValue: 3)
        #expect(DataModelVersion.current >= version)
        let reason = try #require(version.changeReason)
        #expect(reason.localized(preferredLocales: [Locale(identifier: "en")]) ==
            "Where now saves which device recorded a location and which device corrected it.")
    }

    @Test func dataVersion4ExplainsChange() throws {
        let version = DataModelVersion(rawValue: 4)
        #expect(DataModelVersion.current >= version)
        let reason = try #require(version.changeReason)
        #expect(reason.localized(preferredLocales: [Locale(identifier: "en")]) ==
            "Where can now show the model of each device in your history.")
    }

    @Test func publishedReasonIncludesEveryTranslationAndSkipsMissingOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "test.where.data-model-reason",
            "CFBundleDevelopmentRegion": "en",
            "CFBundlePackageType": "BNDL",
        ], format: .xml, options: 0)
        try info.write(to: directory.appending(path: "Info.plist"))
        for (language, strings) in [
            "en": #""reason" = "English reason";"#,
            "fr": #""reason" = "French reason";"#,
            "ja": #""unrelated" = "Unrelated string";"#,
        ] {
            let localization = directory.appending(path: "\(language).lproj")
            try FileManager.default.createDirectory(
                at: localization,
                withIntermediateDirectories: true,
            )
            try Data(strings.utf8).write(to: localization.appending(path: "Localizable.strings"))
        }
        let bundle = try #require(Bundle(url: directory))
        let reason = DataModelChangeReason(resource: "reason", bundle: bundle)
        let published = try JSONDecoder().decode(
            DataModelChangeReason.self,
            from: JSONEncoder().encode(reason),
        )
        #expect(published == DataModelChangeReason(translations: [
            "en": "English reason",
            "fr": "French reason",
        ]))
        #expect(published
            .localized(preferredLocales: [Locale(identifier: "fr-CA")]) == "French reason")
        #expect(published
            .localized(preferredLocales: [Locale(identifier: "ja")]) == "English reason")
    }

    @Test(arguments: [0, -1])
    func invalidWireVersionThrows(value: Int) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DataModelVersion.self, from: Data("\(value)".utf8))
        }
    }

    @Test func wireFormatIsAnInteger() throws {
        let version = DataModelVersion(rawValue: 2)
        #expect(try JSONEncoder().encode(version) == Data("2".utf8))
        #expect(try JSONDecoder().decode(DataModelVersion.self, from: Data("2".utf8)) == version)
    }
}
