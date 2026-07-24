import Foundation
@testable import PortholeCLICore
import PortholeClientKit
import Testing

struct AppResolutionTests {
    private func app(_ name: String, bundle: String, device: String) -> PairedApp {
        PairedApp(
            pairingID: UUID(),
            appName: name,
            bundleID: bundle,
            deviceName: device,
            pairedAt: Date(),
        )
    }

    @Test func noSelectorRequiresExactlyOne() throws {
        let only = app("Where", bundle: "com.stuff.where", device: "iPhone")
        #expect(try AppResolution.resolve(selector: nil, from: [only]) == only)

        #expect(throws: AppResolution.Failure.self) {
            _ = try AppResolution.resolve(selector: nil, from: [])
        }
        #expect(throws: AppResolution.Failure.self) {
            _ = try AppResolution.resolve(
                selector: nil,
                from: [only, app("Other", bundle: "com.stuff.other", device: "iPad")],
            )
        }
    }

    @Test func selectorMatchesBundleExactly() throws {
        let apps = [
            app("Where", bundle: "com.stuff.where", device: "iPhone"),
            app("Other", bundle: "com.stuff.other", device: "iPad"),
        ]
        let match = try AppResolution.resolve(selector: "com.stuff.where", from: apps)
        #expect(match.bundleID == "com.stuff.where")
    }

    @Test func selectorMatchesNameSubstringCaseInsensitively() throws {
        let apps = [app("Where", bundle: "com.stuff.where", device: "Kevin's iPhone")]
        #expect(try AppResolution.resolve(selector: "wher", from: apps).appName == "Where")
        #expect(try AppResolution.resolve(selector: "iphone", from: apps).appName == "Where")
    }

    @Test func ambiguousSelectorThrows() {
        let apps = [
            app("Where", bundle: "com.stuff.where", device: "iPhone"),
            app("Where Dev", bundle: "com.stuff.where.dev", device: "iPad"),
        ]
        #expect(throws: AppResolution.Failure.self) {
            _ = try AppResolution.resolve(selector: "where", from: apps)
        }
    }

    @Test func unknownSelectorThrows() {
        let apps = [app("Where", bundle: "com.stuff.where", device: "iPhone")]
        #expect(throws: AppResolution.Failure.self) {
            _ = try AppResolution.resolve(selector: "nope", from: apps)
        }
    }
}
