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
            Toggle(isOn: trackingBinding) {
                Label(Strings.settingsLocationToggle, systemImage: "location.fill")
            }
            Button {
                Task { await model.requestPermission() }
            } label: {
                Label(Strings.settingsLocationGrant, systemImage: "location.magnifyingglass")
            }
        } header: {
            Text(Strings.settingsLocationHeader)
        } footer: {
            Text(Strings.settingsLocationFooter)
        }
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
