import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

struct DevicesSettingsForm: View {
    let model: DevicesSettingsModel

    var body: some View {
        Form {
            switch model.state {
                case .idle, .loading:
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                case let .failed(failure):
                    DeviceLoadFailureSection(message: failure.message, model: model)
                case .empty:
                    DeviceLoadFailureSection(message: nil, model: model)
                case .loaded:
                    ForEach(model.rows) { row in
                        DeviceSettingsSection(model: model, row: row)
                    }
            }
        }
        .whereFormRoot()
    }
}

private struct DeviceLoadFailureSection: View {
    let message: String?
    let model: DevicesSettingsModel

    var body: some View {
        Section {
            ContentUnavailableView(
                String(localized: .settingsDevicesLoadFailed),
                systemSymbol: .exclamationmarkIcloud,
                description: message.map { Text($0) },
            )
            Button(String(localized: .commonRetry)) {
                Task { await model.retry() }
            }
        }
    }
}

private struct DeviceNicknameSaveButton: View {
    let model: DevicesSettingsModel
    let row: DeviceSettingsRowModel

    var body: some View {
        Button(String(localized: .commonSave)) {
            Task { await model.saveNickname(row) }
        }
        .buttonStyle(.borderless)
        .disabled(!row.canSaveNickname)
    }
}

#if DEBUG
    #Preview { NavigationStack { DevicesSettingsView.snapshotPreviews }.whereBroadwayRoot() }
#endif

/// Form section for one installation's identity, status, local preference, and removal controls.
private struct DeviceSettingsSection: View {
    let model: DevicesSettingsModel
    let row: DeviceSettingsRowModel

    var body: some View {
        Section {
            DeviceNicknameRow(model: model, row: row)

            DeviceRecordingStatusRow(row: row)

            DeviceLastActiveRow(row: row)

            if row.isCurrent {
                CurrentDeviceRecordingControls(model: model, row: row)
            } else {
                DeviceRemovalButton(model: model, row: row)
            }
        } header: {
            DeviceSettingsHeader(row: row)
        } footer: {
            if row.isCurrent {
                Text(String(localized: .settingsDevicesCurrentFooter))
            } else {
                Text(String(localized: .settingsDevicesRemoteFooter))
            }
        }
    }
}

private struct DeviceNicknameRow: View {
    let model: DevicesSettingsModel
    @Bindable var row: DeviceSettingsRowModel

    var body: some View {
        HStack {
            TextField(String(localized: .settingsDevicesName), text: $row.nickname)
                .submitLabel(.done)
                .onSubmit {
                    Task { await model.saveNickname(row) }
                }

            if row.hasUnsavedNickname {
                DeviceNicknameSaveButton(model: model, row: row)
            }
        }
        .disabled(row.isSaving)
        .settingsRow(DevicesSettingsView.Item.deviceName, when: row.isCurrent)
    }
}

private struct DeviceRecordingStatusRow: View {
    let row: DeviceSettingsRowModel
    @Environment(WhereSession.self) private var session

    var body: some View {
        LabeledContent(String(localized: .settingsDevicesStatus)) {
            HStack {
                Image(systemSymbol: statusSymbol)
                    .accessibilityHidden(true)
                Text(statusTitle)
            }
            .foregroundStyle(statusStyle)
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
            if case .applied = session.recordingRuntimeState {
                true
            } else {
                false
            }
        } else {
            true
        }
        return row.status == .recording && runtimeIsAvailable
            ? .primary
            : .secondary
    }
}

private struct DeviceLastActiveRow: View {
    let row: DeviceSettingsRowModel

    var body: some View {
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
    }
}

private struct DeviceRecordingToggle: View {
    let model: DevicesSettingsModel
    @Bindable var row: DeviceSettingsRowModel

    var body: some View {
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
    }
}

private struct DeviceGrantPermissionButton: View {
    let model: DevicesSettingsModel

    var body: some View {
        Button {
            Task { await model.requestPermission() }
        } label: {
            Label(
                String(localized: .settingsDevicesGrant),
                systemSymbol: .locationMagnifyingglass,
            )
        }
    }
}

private struct DeviceOpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openSystemSettings(openURL)
        } label: {
            Label(
                String(localized: .settingsPermissionAlertOpenSettings),
                systemSymbol: .gear,
            )
        }
    }
}

private struct CurrentDeviceRecordingControls: View {
    let model: DevicesSettingsModel
    let row: DeviceSettingsRowModel
    @Environment(WhereSession.self) private var session

    var body: some View {
        DeviceRecordingToggle(model: model, row: row)

        LocationStatusRow(
            status: session.authorizationStatus,
            isTracking: session.isTracking,
        )

        if showGrantButton {
            DeviceGrantPermissionButton(model: model)
        }

        if showOpenSettingsButton {
            DeviceOpenSettingsButton()
        }
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

private struct DeviceSettingsHeader: View {
    let row: DeviceSettingsRowModel

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Label {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: stylesheet.spacing.small) {
                    DeviceSettingsHeaderText(row: row)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                    DeviceSettingsHeaderText(row: row)
                }
            }
        } icon: {
            Image(systemSymbol: row.systemSymbol)
        }
    }
}

private struct DeviceSettingsHeaderText: View {
    let row: DeviceSettingsRowModel

    var body: some View {
        Text(row.displayName)
        if row.isCurrent {
            Text(String(localized: .settingsDevicesThisDevice)).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview("Device Settings Section") {
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
