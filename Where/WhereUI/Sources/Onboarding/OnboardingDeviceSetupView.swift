import SwiftUI
import WhereCore

/// Known-device choices within setup. An empty local discovery remains advisory because sync
/// may still deliver additional devices; Settings retains the same removal control afterward.
struct OnboardingDeviceSetupView: View {
    @Bindable var setup: OnboardingDeviceSetupModel
    let installationContext: InstallationRecordingContext
    @Environment(WhereModel.self) private var model
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            switch setup.discovery {
                case .idle, .loading:
                    ProgressView(String(localized: .onboardingRecordingChecking))
                case .ready:
                    if !setup.existingDevices.isEmpty {
                        devicePicker
                        if setup.replacementDeviceID != nil {
                            Toggle(
                                String(localized: .onboardingDevicesRemoveOld),
                                isOn: $setup.removesOldDevice,
                            )
                            Text(String(localized: .onboardingDevicesReplacementDescription))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: .onboardingDevicesAdditionalDescription))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                case let .failed(error):
                    Label(error.localizedDescription, systemSymbol: .icloudSlash)
                        .foregroundStyle(.secondary)
                    Button(String(localized: .commonRetry)) {
                        Task { await setup.discover(using: model, context: installationContext) }
                    }
            }
        }
    }

    private var devicePicker: some View {
        Menu {
            Picker(
                String(localized: .onboardingDevicesSetup),
                selection: $setup.replacementDeviceID,
            ) {
                Text(String(localized: .onboardingDevicesAdditional))
                    .tag(nil as RecordingDeviceID?)
                ForEach(setup.existingDevices) { device in
                    Text(String(localized: .onboardingDevicesReplace(device.displayName)))
                        .tag(Optional(device.id))
                }
            }
        } label: {
            Label {
                Text(selectedSetupDescription)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemSymbol: .chevronUpChevronDown)
            }
        }
        .accessibilityLabel(String(localized: .onboardingDevicesSetup))
        .accessibilityValue(selectedSetupDescription)
    }

    private var selectedSetupDescription: String {
        if let device = setup.replacementDevice {
            String(localized: .onboardingDevicesReplace(device.displayName))
        } else {
            String(localized: .onboardingDevicesAdditional)
        }
    }
}

#if DEBUG
    #Preview {
        OnboardingView.snapshotPreviews
    }
#endif
