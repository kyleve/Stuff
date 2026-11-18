/// One version observation. A cloud revision is an opaque conditional-save token.
public struct PersistedDataModelVersion: Sendable, Equatable {
    public let version: DataModelVersion
    public let revision: String

    public init(version: DataModelVersion, revision: String) {
        self.version = version
        self.revision = revision
    }
}
