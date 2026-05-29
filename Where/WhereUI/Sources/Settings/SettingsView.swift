import SwiftUI
import WhereCore

/// Settings tab: manual entry, GPS controls, and destructive actions. Filled
/// out in a later step.
struct SettingsView: View {
    @Environment(WhereModel.self) private var model

    var body: some View {
        NavigationStack {
            Text("Settings")
                .navigationTitle("Settings")
        }
    }
}
