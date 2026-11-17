/// An ephemeral widget cache, qualified by the data format and domain that produced it.
struct PersistedWidgetSnapshot: Codable, Equatable {
    let snapshot: WidgetSnapshot
    let version: DataModelVersion
    let domain: DataCompatibilityDomain
}
