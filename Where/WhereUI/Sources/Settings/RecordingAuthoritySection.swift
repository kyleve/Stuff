import SwiftUI
import WhereCore

/// The one account-wide automatic recorder. Device rows remain editors for identity, activity,
/// permission, and archival; assignment changes happen only here.
struct RecordingAuthoritySection: View {
    @Bindable var model: DevicesSettingsModel

    var body: some View {
        Section {
            Picker("Automatic recording", selection: $model.selectedRecordingDeviceID) {
                Text("Off").tag(RecordingDeviceID?.none)
                ForEach(model.rows) { row in
                    Label(row.displayName, systemImage: row.systemImage)
                        .tag(Optional(row.id))
                }
            }
            .onChange(of: model.selectedRecordingDeviceID) { oldValue, newValue in
                guard oldValue != newValue else { return }
                Task { await model.recordingAssignmentChanged() }
            }

            switch model.authorityResolution {
                case .unconfigured:
                    Label("Choose the one device that stays with you.", systemImage: "location")
                        .foregroundStyle(.secondary)
                case let .resolved(assignment):
                    if assignment.deviceID == nil {
                        Label("Automatic recording is Off.", systemImage: "location.slash")
                            .foregroundStyle(.secondary)
                    } else {
                        Label(
                            "Only this device records location automatically.",
                            systemImage: "checkmark.shield",
                        )
                        .foregroundStyle(.secondary)
                    }
                case let .conflict(deviceIDs):
                    Label(
                        "Recording is paused because \(deviceIDs.count) devices were chosen at the same time. Pick one to resolve it.",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .foregroundStyle(.orange)
                case .invalid:
                    Label(
                        "Recording is paused while device changes finish syncing.",
                        systemImage: "icloud.and.arrow.down",
                    )
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Recorder")
        } footer: {
            Text(
                "Every device can still correct your history and add evidence. Transferring the recorder takes effect immediately.",
            )
        }
    }
}
