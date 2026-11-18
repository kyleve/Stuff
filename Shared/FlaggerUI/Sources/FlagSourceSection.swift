import Flagger

struct FlagSourceSection: Identifiable {
    let id: FlagSourceID
    let name: String
    let groups: [FlagGroupSection]
}
