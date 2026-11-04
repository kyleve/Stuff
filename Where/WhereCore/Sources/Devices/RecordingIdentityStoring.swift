/// Device-local identity persistence, composed once by the app. Consent and import recovery
/// remain in the installation sidecar and never enter the identity's Keychain payload.
@MainActor
public protocol RecordingIdentityStoring: AnyObject {
    /// Nil means a confirmed absence. Inaccessible or corrupt identity storage throws.
    func load() throws -> InstallationRecordingIdentity?
    /// Create a previously absent identity. A concurrent creation must not be overwritten.
    func create(_ identity: InstallationRecordingIdentity) throws
    /// Rotate only the expected identity. A stale caller must not replace a newer identity.
    func replace(
        _ identity: InstallationRecordingIdentity,
        expectedDeviceID: RecordingDeviceID,
    ) throws
}
