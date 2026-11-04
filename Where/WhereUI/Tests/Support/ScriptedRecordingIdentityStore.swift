import WhereCore

@MainActor
final class ScriptedRecordingIdentityStore: RecordingIdentityStoring {
    enum Failure: Error { case unavailable, changed }

    var identity: InstallationRecordingIdentity?
    var failure: Failure?
    private(set) var creationCount = 0
    private(set) var replacementCount = 0

    func load() throws -> InstallationRecordingIdentity? {
        if let failure { throw failure }
        return identity
    }

    func create(_ identity: InstallationRecordingIdentity) throws {
        if let failure { throw failure }
        guard self.identity == nil else { throw Failure.changed }
        self.identity = identity
        creationCount += 1
    }

    func replace(
        _ identity: InstallationRecordingIdentity,
        expectedDeviceID: RecordingDeviceID,
    ) throws {
        if let failure { throw failure }
        guard self.identity?.deviceID == expectedDeviceID else { throw Failure.changed }
        self.identity = identity
        replacementCount += 1
    }
}
