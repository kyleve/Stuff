/// One version observation. A cloud revision is an opaque conditional-save token.
public struct PersistedDataModelVersion: Sendable, Equatable {
    public let version: DataModelVersion
    public let revision: String
    let changeReason: DataModelChangeReason?

    public init(version: DataModelVersion, revision: String) {
        self.init(version: version, revision: revision, changeReason: nil)
    }

    init(version: DataModelVersion, revision: String, changeReason: DataModelChangeReason?) {
        self.version = version
        self.revision = revision
        self.changeReason = changeReason
    }
}
