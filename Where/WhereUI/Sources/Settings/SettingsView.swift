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
            .navigationTitle("Settings")
            .alert("Location access needed", isPresented: $model.permissionDenied) {
                Button("Open Settings") { openSystemSettings() }
                Button("Not now", role: .cancel) {}
            } message: {
                Text(
                    "Where needs Always location access to log which region you're in. You can grant it in the Settings app.",
                )
            }
        }
    }

    private var trackingSection: some View {
        Section {
            Toggle(isOn: trackingBinding) {
                Label("Track in the background", systemImage: "location.fill")
            }
            Button {
                Task { await model.requestPermission() }
            } label: {
                Label("Grant location access", systemImage: "location.magnifyingglass")
            }
        } header: {
            Text("Location")
        } footer: {
            Text(
                "Where watches for visits and big moves to figure out which region you're in. It needs Always access and a little patience.",
            )
        }
    }

    private var manualEntrySection: some View {
        Section {
            NavigationLink {
                ManualDayEntryView()
            } label: {
                Label("Log or override a day", systemImage: "calendar.badge.plus")
            }
        } header: {
            Text("Manual entry")
        } footer: {
            Text("Backfill a trip the GPS missed, or correct a day by hand.")
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
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    verbatim: "This removes every sample, manual day, and piece of evidence in \(model.selectedYear). It can't be undone.",
                )
            }
        } header: {
            Text("Data")
        } footer: {
            Text(verbatim: "Acts on the year selected on the Primary tab (\(model.selectedYear)).")
        }
    }

    private var eraseTitle: String {
        "Erase \(model.selectedYear) data"
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
