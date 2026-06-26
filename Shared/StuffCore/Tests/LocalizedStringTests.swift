import Foundation
import StuffCore
import Testing

struct LocalizedStringTests {
    @Test func resolvesViaBuilder() {
        let string = LocalizedString { _ in "hello" }
        #expect(string.localized() == "hello")
    }

    @Test func defaultsToNilConfig() {
        let string = LocalizedString { $0?.locale.identifier ?? "default" }
        #expect(string.localized() == "default")
    }

    @Test func passesConfigToBuilder() {
        let string = LocalizedString { $0?.locale.identifier ?? "default" }
        let config = LocalizationConfig(locale: Locale(identifier: "fr_FR"))
        #expect(string.localized(config) == "fr_FR")
    }
}
