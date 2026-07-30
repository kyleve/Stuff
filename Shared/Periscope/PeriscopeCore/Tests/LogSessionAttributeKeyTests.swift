import Foundation
import PeriscopeCore
import Testing

struct LogSessionAttributeKeyTests {
    @Test func keysWithTheSameNameAreTheSameKey() {
        #expect(LogSessionAttributeKey("commit") == .commit)
        #expect(LogSessionAttributeKey("commit") != .commitStatus)
    }

    @Test func describesItselfAsItsName() {
        #expect(String(describing: LogSessionAttributeKey.optimizationLevel) ==
            "optimization-level")
    }

    /// The names are baked into every stored session row and every exported
    /// payload, so renaming one silently orphans the attribute on existing
    /// data. Pinned here so a rename has to be a deliberate edit.
    @Test func wellKnownKeysHaveStableNames() {
        #expect(LogSessionAttributeKey.commit.rawValue == "commit")
        #expect(LogSessionAttributeKey.commitStatus.rawValue == "commit-status")
        #expect(LogSessionAttributeKey.configuration.rawValue == "configuration")
        #expect(LogSessionAttributeKey.optimizationLevel.rawValue == "optimization-level")
        #expect(LogSessionAttributeKey.compilationMode.rawValue == "compilation-mode")
    }

    @Test func commitStatusNamesAreStable() {
        #expect(LogSessionAttributeKey.CommitStatus.clean.rawValue == "clean")
        #expect(LogSessionAttributeKey.CommitStatus.dirty.rawValue == "dirty")
        #expect(LogSessionAttributeKey.CommitStatus(rawValue: "probably-fine") == nil)
    }

    @Test func roundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(LogSessionAttributeKey.compilationMode)
        let decoded = try JSONDecoder().decode(LogSessionAttributeKey.self, from: data)
        #expect(decoded == .compilationMode)
    }

    @Test func keysADictionaryAsAJSONObject() throws {
        let data = try JSONEncoder().encode([LogSessionAttributeKey.commit: "a18a9309c5d6"])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(json == ["commit": "a18a9309c5d6"])
    }
}
