import SwiftUI
import UIKit
import WhereCore

/// Settings tab: location permission + tracking, retroactive manual entry,
/// and the destructive "erase a year" action.
struct SettingsView: View {
    @Environment(WhereModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var showClearConfirmation = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                trackingSection
                remindersSection
                manualEntrySection
                dataSection
            }
            .navigationTitle(Strings.settingsTitle)
            .alert(Strings.settingsPermissionAlertTitle, isPresented: $model.permissionDenied) {
                Button(Strings.settingsPermissionAlertOpenSettings) { openSystemSettings() }
                Button(Strings.settingsPermissionAlertNotNow, role: .cancel) {}
            } message: {
                Text(Strings.settingsPermissionAlertMessage)
            }
        }
    }

    private var trackingSection: some View {
        Section {
            LocationStatusRow(status: model.authorizationStatus, isTracking: model.isTracking)

            Toggle(isOn: trackingBinding) {
                Label(Strings.settingsLocationToggle, systemImage: "location.fill")
            }

            if showGrantButton {
                Button {
                    Task { await model.requestPermission() }
                } label: {
                    Label(Strings.settingsLocationGrant, systemImage: "location.magnifyingglass")
                }
            }

            if showOpenSettingsButton {
                Button {
                    openSystemSettings()
                } label: {
                    Label(Strings.settingsPermissionAlertOpenSettings, systemImage: "gear")
                }
            }
        } header: {
            Text(Strings.settingsLocationHeader)
        } footer: {
            Text(Strings.settingsLocationFooter)
        }
    }

    /// Re-requesting only helps before the user has made a final decision.
    private var showGrantButton: Bool {
        switch model.authorizationStatus {
            case .notDetermined, .whenInUse: true
            default: false
        }
    }

    /// Once access is denied/restricted (or stuck at When-In-Use), the only way
    /// forward is the Settings app.
    private var showOpenSettingsButton: Bool {
        switch model.authorizationStatus {
            case .denied, .restricted, .whenInUse: true
            default: false
        }
    }

    private var remindersSection: some View {
        @Bindable var model = model
        return Section {
            Toggle(isOn: $model.remindersEnabled) {
                Label(Strings.settingsRemindersToggle, systemImage: "bell.badge")
            }

            if model.remindersEnabled {
                DatePicker(
                    Strings.settingsReminderTime,
                    selection: $model.reminderTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !model.notificationsAuthorized {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label(Strings.settingsRemindersOpenSettings, systemImage: "bell.slash")
                    }
                }
            }
        } header: {
            Text(Strings.settingsRemindersHeader)
        } footer: {
            Text(remindersFooter)
        }
    }

    private var remindersFooter: String {
        if model.remindersEnabled, !model.notificationsAuthorized {
            return Strings.settingsRemindersDeniedFooter
        }
        return Strings.settingsRemindersFooter
    }

    private var manualEntrySection: some View {
        Section {
            NavigationLink {
                ManualDayEntryView()
            } label: {
                Label(Strings.settingsManualLink, systemImage: "calendar.badge.plus")
            }
        } header: {
            Text(Strings.settingsManualHeader)
        } footer: {
            Text(Strings.settingsManualFooter)
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(eraseTitle, systemImage: "trash")
            }
            .confirmationDialog(
                eraseTitle,
                isPresented: $showClearConfirmation,
                titleVisibility: .visible,
            ) {
                Button(eraseTitle, role: .destructive) {
                    Task { await model.clearSelectedYear() }
                }
                Button(Strings.settingsDataCancel, role: .cancel) {}
            } message: {
                Text(Strings.settingsDataConfirmMessage(year: model.selectedYear))
            }
        } header: {
            Text(Strings.settingsDataHeader)
        } footer: {
            Text(Strings.settingsDataFooter(year: model.selectedYear))
        }
    }

    private var eraseTitle: String {
        Strings.settingsDataErase(year: model.selectedYear)
    }

    private var trackingBinding: Binding<Bool> {
        Binding(
            get: { model.isTracking },
            set: { isOn in
                Task {
                    if isOn {
                        await model.startTracking()
                    } else {
                        await model.stopTracking()
                    }
                }
            },
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#if DEBUG
    #Preview {
        SettingsView()
            .environment(PreviewSupport.loadedModel())
    }
#endif
