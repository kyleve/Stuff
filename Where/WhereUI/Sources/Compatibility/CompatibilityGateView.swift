import LifecycleKit
import SwiftUI
import WhereCore

/// Connects the blocked presentation to the bootstrap without opening a normal app scope.
struct CompatibilityGateView: View {
    let model: WhereModel
    @State private var showsRecording = false
    var body: some View {
        DataCompatibilityView(
            state: model.compatibility.state,
            updates: model.updateAvailability,
            retry: { Task { await model.compatibility.refresh() } },
            manageRecording: { showsRecording = true },
        )
        .sheet(isPresented: $showsRecording) { CompatibilityRecordingRoleSheet(model: model) }
        .onChange(of: model.compatibility.isCompatible) { _, compatible in
            if compatible { showsRecording = false }
        }
    }
}

struct CompatibilityRecordingRoleSheet: View {
    let model: WhereModel
    @State private var content = CompatibilityRecordingRoleModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch content.state {
                    case .loading: ProgressView(String(localized: .compatibilityChecking))
                    case let .failed(message):
                        Text(message)
                        Button(String(localized: .commonRetry)) {
                            Task { await content.load(model: model) }
                        }
                    case let .loaded(role): roleContent(role)
                }
            }
            .navigationTitle(String(localized: .recordingRoleTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) { dismiss() }
                }
            }
        }
        .task { await content.load(model: model) }
    }

    private func roleContent(_ role: RecordingDeviceRoleModel) -> some View {
        @Bindable var role = role
        return RecordingDeviceRoleView(
            state: role.state,
            recoveryReview: $role.recoveryReview,
            reviewRecovery: { role.reviewRecovery() },
            recover: { history in
                Task {
                    await role.recover(history: history); await model
                        .compatibility.refresh()
                }
            },
            canApprove: false,
            choose: { recording in
                Task {
                    _ = await role.choose(recording: recording); await model
                        .compatibility.refresh()
                }
            },
            retry: {
                Task {
                    await role.refresh(); await model.compatibility.refresh()
                }
            },
            approve: {},
            cancel: {
                Task {
                    await role.cancelRequest(); await model.compatibility
                        .refresh()
                }
            },
        )
        .task { await role.run() }
    }
}

#if DEBUG
    #Preview {
        CompatibilityGateView(model: PreviewSupport.onboardingModel()).whereBroadwayRoot()
    }

#endif
