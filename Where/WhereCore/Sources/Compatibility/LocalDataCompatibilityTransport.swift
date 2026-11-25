/// Local stores use the build's data format. The coordinator still checks and saves the durable
/// floor before granting access, so reinstalling an older build cannot lower it.
public struct LocalDataCompatibilityTransport: DataCompatibilityTransport {
    private let version: DataModelVersion

    public init(version: DataModelVersion) {
        self.version = version
    }

    public func domain() async throws -> DataCompatibilityDomain {
        .local
    }

    public func read(domain: DataCompatibilityDomain) async throws -> PersistedDataModelVersion? {
        guard domain == .local else { throw DataCompatibilityTransportError.accountChanged }
        return observation
    }

    public func advance(
        domain: DataCompatibilityDomain,
        from _: PersistedDataModelVersion?,
        to version: DataModelVersion,
    ) async throws -> PersistedDataModelVersion {
        guard domain == .local else { throw DataCompatibilityTransportError.accountChanged }
        guard version == self.version else { throw DataCompatibilityTransportError.conflict }
        return observation
    }

    public func accountChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    private var observation: PersistedDataModelVersion {
        .init(
            version: version,
            revision: "local-\(version.rawValue)",
            changeReason: version.changeReason,
        )
    }
}
