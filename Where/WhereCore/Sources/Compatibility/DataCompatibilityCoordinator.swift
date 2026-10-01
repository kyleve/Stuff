import Foundation

/// Coordinates feature activation without making app installation itself upgrade shared data.
public struct DataCompatibilityCoordinator: Sendable {
    private let store: any WhereStore
    public let currentDeviceID: RecordingDeviceID

    public init(store: any WhereStore, currentDeviceID: RecordingDeviceID) {
        self.store = store
        self.currentDeviceID = currentDeviceID
    }

    public func status() async throws -> DataCompatibilityStatus {
        try await store.dataCompatibility()
    }

    public func requireAccess() async throws {
        try await status().requireAccess()
    }

    public func updates() -> AsyncStream<Void> {
        store.changes()
    }

    public func publishCapability(at date: Date) async throws {
        try await store.publishDataCapability(for: currentDeviceID, at: date)
    }

    public func reviewActivation(requiring version: DataCompatibilityVersion) async throws
        -> DataCompatibilityActivationReview
    {
        try await store.readSnapshot {
            let status = try await store.dataCompatibility()
            try DataCompatibilityStatus(
                supportedVersion: status.supportedVersion,
                requiredVersion: version,
            ).requireAccess()
            let generation = try await store.dataGeneration()
            let devices = try await store.recordingDevices()
            let capabilities = try await store.deviceDataCapabilities()
            let byDevice = Dictionary(uniqueKeysWithValues: capabilities.map { (
                $0.deviceID,
                $0.supportedVersion,
            ) })
            let affected: [DataCompatibilityActivationReview.AffectedDevice] = version > status
                .requiredVersion
                ? devices.filter { $0.removedAt == nil }.compactMap { device in
                    let supported = device.id == currentDeviceID ? status
                        .supportedVersion : byDevice[device.id]
                    if let supported, supported >= version { return nil }
                    return .init(
                        id: device.id,
                        displayName: device.displayName,
                        supportedVersion: supported,
                    )
                }.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
                : []
            return DataCompatibilityActivationReview(
                requiredVersion: version,
                previousVersion: status.requiredVersion,
                generationID: generation.id,
                affectedDevices: affected,
            )
        }
    }

    /// The review, requirement increase, and first dependent write share the same transaction.
    /// A changed warning returns a fresh review; confirmation never becomes a lasting preference.
    @discardableResult
    public func perform<T: Sendable>(
        requiring version: DataCompatibilityVersion,
        approval: DataCompatibilityActivationApproval,
        _ operation: @Sendable () async throws -> T,
    ) async throws -> T {
        try await store.perform {
            let review = try await reviewActivation(requiring: version)
            try review.requireApproval(approval)
            try await store.requireDataCompatibility(version)
            return try await operation()
        }
    }
}
