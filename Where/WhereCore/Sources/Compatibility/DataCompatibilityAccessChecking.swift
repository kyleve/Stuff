/// A process-local read of the app's evidence. Extensions never consult CloudKit themselves.
public protocol DataCompatibilityAccessChecking: Sendable {
    func requireAccess(version: DataModelVersion) throws -> DataCompatibilityReceipt
}

public struct AppGroupDataAccess: DataCompatibilityAccessChecking {
    private let appGroupIdentifier: String

    public init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    public func requireAccess(version: DataModelVersion) throws -> DataCompatibilityReceipt {
        try FileDataCompatibilityReceipt.shared(appGroupIdentifier: appGroupIdentifier)
            .requireAccess(version: version)
    }
}

extension FileDataCompatibilityReceipt: DataCompatibilityAccessChecking {
    public nonisolated func requireAccess(version: DataModelVersion) throws
        -> DataCompatibilityReceipt
    {
        guard let receipt = try load() else {
            throw DataCompatibilityFailure.recordingDeviceRequired
        }
        try receipt.requireAccess(version: version)
        return receipt
    }
}

/// Preview compositions supply a concrete receipt instead of bypassing the access boundary.
public struct FixedDataCompatibilityAccess: DataCompatibilityAccessChecking {
    private let receipt: DataCompatibilityReceipt

    public init(receipt: DataCompatibilityReceipt) {
        self.receipt = receipt
    }

    public func requireAccess(version: DataModelVersion) throws -> DataCompatibilityReceipt {
        try receipt.requireAccess(version: version)
        return receipt
    }
}
