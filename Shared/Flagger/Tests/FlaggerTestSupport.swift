@_spi(FlaggerUI) @testable import Flagger
import Foundation

struct TestFlags: FeatureFlagGroup {
    static let id = FeatureFlagGroupID("test")
    static let name = "Test Flags"

    let liveBoolean = Flag<Bool, LiveUpdating>(
        "live-boolean",
        name: "Live Boolean",
        default: false,
    )
    let liveString = Flag<String, LiveUpdating>(
        "live-string",
        name: "Live String",
        default: "default",
    )
    let launchString = Flag<String, ReadOnceOnLaunch>(
        "launch-string",
        name: "Launch String",
        default: "default",
    )
    let firstNumber = Flag<Int, ReadOnceOnFirstAccess>(
        "first-number",
        name: "First Number",
        default: 1,
    )
}

enum TestFlagSource: FlagSource {
    static let id = FlagSourceID("tests")
    static let name = "Tests"
    static let groups = FeatureFlagGroupRegistry { TestFlags.self }
}

struct StringFlags: FeatureFlagGroup {
    static let id = FeatureFlagGroupID("test")
    static let name = "Test Flags"

    let liveBoolean = Flag<String, LiveUpdating>(
        "live-boolean",
        name: "Live Boolean",
        default: "false",
    )
}

enum StringFlagSource: FlagSource {
    static let id = FlagSourceID("tests")
    static let name = "Tests"
    static let groups = FeatureFlagGroupRegistry { StringFlags.self }
}

let testSources = FlagSourceRegistry { TestFlagSource.self }
let stringSources = FlagSourceRegistry { StringFlagSource.self }

func makeFlagger() async throws -> Flagger {
    try await Flagger.open(sources: testSources, storage: .inMemory)
}

func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appendingPathExtension("store")
}
