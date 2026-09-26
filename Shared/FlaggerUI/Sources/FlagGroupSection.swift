import Flagger

struct FlagGroupSection: Identifiable {
    let id: FeatureFlagGroupID
    let name: String
    let flags: [FlagSnapshot]
}
