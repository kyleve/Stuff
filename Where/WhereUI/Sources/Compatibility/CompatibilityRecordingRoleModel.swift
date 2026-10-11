import Observation
import WhereCore

/// Loads role management through the bootstrap while normal app services are unavailable.
@MainActor
@Observable
final class CompatibilityRecordingRoleModel {
    enum State { case loading, loaded(RecordingDeviceRoleModel), failed(String) }
    private(set) var state: State = .loading

    func load(model: WhereModel) async {
        state = .loading
        do {
            guard let coordination = try await model.recordingDeviceCoordination() else {
                state = .failed(String(localized: .compatibilityVerificationFailed))
                return
            }
            let role = RecordingDeviceRoleModel(
                coordination: coordination,
                currentDeviceID: model.installationRecordingContext.currentDevice.id,
                selectionChanged: nil,
                approve: nil,
            )
            await role.refresh()
            guard !Task.isCancelled else { return }
            state = .loaded(role)
        } catch {
            state = .failed(error.localizedDescription)
            WhereLog.root(WhereCompatibilityLog.self)(attachments: [.error(
                error,
                name: "recording-recovery-bootstrap-error",
            )]) {
                .verificationFailed(description: error.localizedDescription)
            }
        }
    }
}
