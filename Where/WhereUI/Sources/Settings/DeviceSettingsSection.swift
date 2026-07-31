import SwiftUI
import WhereCore

/// Form section for one device. It binds directly to the row model and sends
/// async effects through the owning Devices model.
struct DeviceSettingsSection: View {
    let model: DevicesSettingsModel
    @Bindable var row: DeviceSettingsRowModel

    @Environment(WhereSession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var isConfirmingArchive = false

    var body: some View {
        Section {
            Toggle(
                String(localized: .settingsDevicesAutomaticRecording),
                isOn: $row.isEnabled,
            )
            .settingsRow(DevicesSettingsView.Item.automaticRecording)
            .disabled(row.isBusy)
            .onChange(of: row.isEnabled) { oldValue, newValue in
                guard oldValue != newValue else { return }
                Task {
                    await model.setEnabled(
                        newValue,
                        row: row,
                    )
                }
            }

            TextField(String(localized: .settingsDevicesName), text: $row.nickname)
                .settingsRow(DevicesSettingsView.Item.deviceName)
                .disabled(row.isBusy)
                .onSubmit {
                    Task { await model.rename(row) }
                }

            LabeledContent(String(localized: .settingsDevicesStatus)) {
                HStack {
                    Image(systemName: statusSymbol)
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
                            systemImage: "location.magnifyingglass",
                        )
                    }
                }

                if showOpenSettingsButton {
                    Button {
                        openSystemSettings(openURL)
                    } label: {
                        Label(
                            String(localized: .settingsPermissionAlertOpenSettings),
                            systemImage: "gear",
                        )
                    }
                }
            } else {
                Button(
                    String(localized: .settingsDevicesArchive),
                    systemImage: "archivebox",
                    role: .destructive,
                ) {
                    isConfirmingArchive = true
                }
                .disabled(row.isBusy)
                .confirmationDialog(
                    String(localized: .settingsDevicesArchiveConfirmTitle),
                    isPresented: $isConfirmingArchive,
                    titleVisibility: .visible,
                ) {
                    Button(String(localized: .settingsDevicesArchive), role: .destructive) {
                        Task { await model.archive(row) }
                    }
                } message: {
                    Text(String(localized: .settingsDevicesArchiveConfirmMessage))
                }
            }
        } header: {
            Label {
                HStack {
                    Text(row.displayName)
                    if row.isCurrent {
                        Text(String(localized: .settingsDevicesThisDevice))
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: row.systemImage)
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
        if row.isPending {
            return String(localized: .settingsDevicesStatusPending)
        }
        switch row.status {
            case .recording: return String(localized: .settingsDevicesStatusRecording)
            case .off: return String(localized: .settingsDevicesStatusOff)
            case .permissionRequired:
                return String(localized: .settingsDevicesStatusPermissionRequired)
        }
    }

    private var statusSymbol: String {
        if row.isPending { return "clock.arrow.trianglehead.counterclockwise.rotate.90" }
        return switch row.status {
            case .recording: "location.fill"
            case .off: "location.slash"
            case .permissionRequired: "exclamationmark.triangle"
        }
    }

    private var statusStyle: HierarchicalShapeStyle {
        row.status == .recording && !row.isPending ? .primary : .secondary
    }

    private var showGrantButton: Bool {
        guard row.isEnabled else { return false }
        return switch session.authorizationStatus {
            case .notDetermined, .whenInUse: true
            case .restricted, .denied, .always: false
        }
    }

    private var showOpenSettingsButton: Bool {
        guard row.isEnabled else { return false }
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
