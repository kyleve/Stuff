import Foundation
import SwiftData

extension SwiftDataStore {
    public func dataCompatibility() throws -> DataCompatibilityStatus {
        // A fresh peer observes external commits even while a domain transaction is suspended.
        // Its pending requirement also participates, so activation cannot write above our support.
        do {
            let committed = try Self.requiredDataVersion(in: ModelContext(modelContainer))
            let pending = try Self.requiredDataVersion(in: compatibilityContext())
            return dataCompatibilityStatus(requiredVersion: max(committed, pending))
        } catch let error as DataCompatibilityError {
            throw error
        } catch {
            throw DataCompatibilityError.verificationFailed(description: error.localizedDescription)
        }
    }

    func assertDataCompatible() throws {
        try dataCompatibility().requireAccess()
    }

    public func requireDataCompatibility(_ version: DataCompatibilityVersion) throws {
        let context = try mutationContext()
        let status = try dataCompatibility()
        try DataCompatibilityStatus(
            supportedVersion: status.supportedVersion,
            requiredVersion: version,
        ).requireAccess()
        if version > status.requiredVersion {
            context.insert(SDDataCompatibilityRequirement(version: version))
        }
    }

    public func deviceDataCapabilities() throws -> [DeviceDataCapability] {
        let records = try compatibilityContext().fetch(FetchDescriptor<SDDeviceDataCapability>())
        let values = try records.map { try $0.toValue() }
        return Dictionary(grouping: values, by: \.deviceID)
            .compactMap { $0.value.max(by: DeviceDataCapability.isOlder) }
            .sorted { $0.deviceID.rawValue.uuidString < $1.deviceID.rawValue.uuidString }
    }

    public func publishDataCapability(for deviceID: RecordingDeviceID, at date: Date) async throws {
        try await performCompatibilityMaintenance {
            try await self.writeDataCapability(for: deviceID, at: date)
        }
    }

    private func writeDataCapability(for deviceID: RecordingDeviceID, at date: Date) throws {
        let context = compatibilityContext()
        let storedDeviceID = deviceID.rawValue
        let records = try context
            .fetch(FetchDescriptor<SDDeviceDataCapability>(predicate: #Predicate {
                $0.deviceID == storedDeviceID
            }))
        let values = try records.map { try $0.toValue() }
        let latest = values.max(by: DeviceDataCapability.isOlder)
        let revision = try RecordingDevicePolicyResolver.nextRevision(
            after: latest?.revision,
            for: deviceID,
        )
        let capability = DeviceDataCapability(
            deviceID: deviceID,
            supportedVersion: dataCompatibilityStatus(requiredVersion: .initial).supportedVersion,
            revision: revision,
            reportedAt: date,
        )
        // Keep reports immutable so delayed CloudKit delivery cannot overwrite a newer revision.
        context.insert(SDDeviceDataCapability(value: capability))
    }

    private static func requiredDataVersion(in context: ModelContext) throws
        -> DataCompatibilityVersion
    {
        try context.fetch(FetchDescriptor<SDDataCompatibilityRequirement>())
            .reduce(.initial) { try max($0, $1.version()) }
    }
}

/// Global, immutable requirements survive every user-data generation rotation.
@Model
final class SDDataCompatibilityRequirement {
    var id: UUID?
    var requiredVersion: Int?

    init(version: DataCompatibilityVersion) {
        id = UUID()
        requiredVersion = version.rawValue
    }

    func version() throws -> DataCompatibilityVersion {
        guard id != nil, let requiredVersion, requiredVersion > 0 else {
            throw DataCompatibilityError.invalidMetadata
        }
        return DataCompatibilityVersion(rawValue: requiredVersion)
    }
}

/// Immutable installation-owned reports, separate from user-editable device metadata and consent.
@Model
final class SDDeviceDataCapability {
    var deviceID: UUID?
    var supportedVersion: Int?
    var revision: Int64?
    var reportedAt: Date?

    init(value: DeviceDataCapability) {
        update(from: value)
    }

    func update(from value: DeviceDataCapability) {
        deviceID = value.deviceID.rawValue
        supportedVersion = value.supportedVersion.rawValue
        revision = value.revision
        reportedAt = value.reportedAt
    }

    func toValue() throws -> DeviceDataCapability {
        guard let deviceID, let supportedVersion, supportedVersion > 0,
              let revision, revision >= 0, let reportedAt
        else {
            throw DataCompatibilityError.invalidMetadata
        }
        return DeviceDataCapability(
            deviceID: .init(rawValue: deviceID),
            supportedVersion: .init(rawValue: supportedVersion),
            revision: revision,
            reportedAt: reportedAt,
        )
    }
}
