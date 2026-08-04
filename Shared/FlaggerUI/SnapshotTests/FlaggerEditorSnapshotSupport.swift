import Flagger

struct SnapshotFlags: FeatureFlagGroup {
    static let id = FeatureFlagGroupID("editor")
    static let name = "Editor"

    let boolean = Flag<Bool, LiveUpdating>(
        "boolean",
        name: "Boolean experiment",
        detail: "A live Boolean flag",
        default: true,
    )
    let configuration = Flag<[String: Int], ReadOnceOnLaunch>(
        "configuration",
        name: "JSON configuration",
        detail: "Applies when this scope is created",
        default: ["maximum": 10],
    )
}

enum SnapshotFlagSource: FlagSource {
    static let id = FlagSourceID("snapshot-module")
    static let name = "Snapshot Module"
    static let groups = FeatureFlagGroupRegistry { SnapshotFlags.self }
}
