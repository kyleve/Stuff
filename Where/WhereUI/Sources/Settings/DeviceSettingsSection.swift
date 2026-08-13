import SFSafeSymbols
import SwiftUI
import WhereCore

/// Form section for one installation's identity, status, local preference, and removal controls.
struct DeviceSettingsSection: View {
    let model: DevicesSettingsModel
    @Bindable var row: DeviceSettingsRowModel

    @Environment(WhereSession.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.stylesheet) private var stylesheet
    @State private var isConfirmingRemoval = false

    var body: some View {
        Section {
            HStack {
                TextField(String(localized: .settingsDevicesName), text: $row.nickname)
                    .submitLabel(.done)
                    .onSubmit {
                        Task { await model.saveNickname(row) }
                    }

                if row.hasUnsavedNickname {
                    Button(String(localized: .commonSave)) {
                        Task { await model.saveNickname(row) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(!row.canSaveNickname)
                }
            }
            .disabled(row.isSaving)
            .settingsRow(DevicesSettingsView.Item.deviceName, when: row.isCurrent)

            LabeledContent(String(localized: .settingsDevicesStatus)) {
                HStack {
                    Image(systemSymbol: statusSymbol)
                        .accessibilityHidden(true)
                    Text(statusTitle)
                }
                .foregroundStyle(statusStyle)
            }

            LabeledContent(String(localized: .settingsDevicesLastActive)) {
                Text(
                    row.lastSeenAt,
                    format: .dateTime
                        .month(.abbreviated)
                        .day()
                        .year()
                        .hour()
                        .minute(),
                )
                .foregroundStyle(.secondary)
            }

            if row.isCurrent {
                Toggle(
                    String(localized: .settingsDevicesAutomaticRecording),
                    isOn: $row.isEnabled,
                )
                .disabled(row.isSaving)
                .settingsRow(DevicesSettingsView.Item.automaticRecording)
                .onChange(of: row.isEnabled) { oldValue, newValue in
                    guard oldValue != newValue else { return }
                    Task { await model.recordingPreferenceChanged(for: row) }
                }

                LocationStatusRow(
                    status: session.authorizationStatus,
                    isTracking: session.isTracking,
                )

                if showGrantButton {
                    Button {
                        Task { await model.requestPermission() }
                    } label: {
                        Label(
                            String(localized: .settingsDevicesGrant),
                            systemSymbol: .locationMagnifyingglass,
                        )
                    }
                }

                if showOpenSettingsButton {
                    Button {
                        openSystemSettings(openURL)
                    } label: {
                        Label(
                            String(localized: .settingsPermissionAlertOpenSettings),
                            systemSymbol: .gear,
                        )
                    }
                }
            } else {
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    HStack {
                        Image(systemSymbol: .trash)
                        Text(String(localized: .settingsDevicesRemove))
                    }
                    .foregroundStyle(.red)
                }
                .disabled(row.isSaving)
                .confirmationDialog(
                    String(localized: .settingsDevicesRemoveConfirmTitle),
                    isPresented: $isConfirmingRemoval,
                    titleVisibility: .visible,
                ) {
                    Button(String(localized: .settingsDevicesRemove), role: .destructive) {
                        Task { await model.remove(row) }
                    }
                } message: {
                    Text(String(localized: .settingsDevicesRemoveConfirmMessage))
                }
            }
        } header: {
            Label {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: stylesheet.spacing.small) {
                        Text(row.displayName)
                        if row.isCurrent {
                            Text(String(localized: .settingsDevicesThisDevice))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                        Text(row.displayName)
                        if row.isCurrent {
                            Text(String(localized: .settingsDevicesThisDevice))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } icon: {
                Image(systemSymbol: row.systemSymbol)
            }
        } footer: {
            if row.isCurrent {
                Text(String(localized: .settingsDevicesCurrentFooter))
            } else {
                Text(String(localized: .settingsDevicesRemoteFooter))
            }
        }
    }

    private var statusTitle: String {
        if row.isCurrent, case .unavailable = session.recordingRuntimeState {
            return String(localized: .settingsDevicesStatusUnavailable)
        }
        switch row.status {
            case .unknown: return String(localized: .settingsDevicesStatusPending)
            case .recording: return String(localized: .settingsDevicesStatusRecording)
            case .off: return String(localized: .settingsDevicesStatusOff)
            case .permissionRequired:
                return String(localized: .settingsDevicesStatusPermissionRequired)
        }
    }

    private var statusSymbol: SFSymbol {
        if row.isCurrent, case .unavailable = session.recordingRuntimeState {
            return .exclamationmarkTriangle
        }
        return switch row.status {
            case .unknown: .clockArrowTriangleheadCounterclockwiseRotate90
            case .recording: .locationFill
            case .off: .locationSlash
            case .permissionRequired: .exclamationmarkTriangle
        }
    }

    private var statusStyle: HierarchicalShapeStyle {
        let runtimeIsAvailable = if row.isCurrent {
            if case .applied = session.recordingRuntimeState { true } else { false }
        } else {
            true
        }
        return row.status == .recording && runtimeIsAvailable
            ? .primary
            : .secondary
    }

    private var showGrantButton: Bool {
        guard row.isCurrent, row.isEnabled else { return false }
        return switch session.authorizationStatus {
            case .notDetermined, .whenInUse: true
            case .restricted, .denied, .always: false
        }
    }

    private var showOpenSettingsButton: Bool {
        guard row.isCurrent else { return false }
        return switch session.authorizationStatus {
            case .denied, .restricted, .whenInUse: true
            case .notDetermined, .always: false
        }
    }
}

#if DEBUG
    #Preview {
        let session = PreviewSupport.loadedSession()
        let model = DevicesSettingsModel(
            session: session,
            configurations: PreviewSupport.recordingDeviceConfigurations(),
        )
        Form {
            DeviceSettingsSection(model: model, row: model.rows[0])
        }
        .environment(session)
    }
#endif
