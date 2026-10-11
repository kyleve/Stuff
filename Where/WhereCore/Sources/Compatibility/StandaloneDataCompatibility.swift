import Foundation

/// Short-lived extensions may use the existing contract but never advance it.
public enum StandaloneDataCompatibility {
    public static func requireAccess(to store: any WhereStore) async throws {
        try await validate(required: store.requiredDataCompatibilityVersion(), supported: .current)
    }

    static func validate(
        required: DataCompatibilityVersion,
        supported: DataCompatibilityVersion,
    ) throws {
        if required > supported { throw DataCompatibilityError.updateRequired(required) }
        if required < supported { throw DataCompatibilityError.recordingDeviceUpdateRequired }
    }
}
