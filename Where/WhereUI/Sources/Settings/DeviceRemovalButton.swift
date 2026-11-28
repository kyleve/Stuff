import SFSafeSymbols
import SwiftUI
import WhereCore

struct DeviceRemovalButton: View {
    let model: DevicesSettingsModel
    let row: DeviceSettingsRowModel
    @State private var isConfirmingRemoval = false

    var body: some View {
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
}

#if DEBUG
    #Preview { NavigationStack { DevicesSettingsView.snapshotPreviews }.whereBroadwayRoot() }
#endif
