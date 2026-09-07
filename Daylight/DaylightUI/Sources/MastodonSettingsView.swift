import BroadwayUI
import DaylightMastodon
import SnapshotKit
import SwiftUI

struct MastodonSettingsView: View {
    @Bindable var model: DaylightModel
    var body: some View {
        Form {
            Section {
                TextField(.mastodonServer, text: $model.server).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().keyboardType(.URL)
                SecureField(.mastodonToken, text: $model.token).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(.mastodonConnect) { Task { await model.connect() } }.disabled(model.working)
                Text(.mastodonTokenHelp).font(.footnote).foregroundStyle(.secondary)
            }
            if let connection = model.account.connection {
                Section {
                    LabeledContent { Text(connection.username) } label: { Text(.mastodonAccount) }
                    Picker(selection: $model.account.visibility) {
                        ForEach(MastodonSettings.Visibility.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    } label: { Text(.mastodonVisibility) }
                    TextField(.mastodonCaption, text: $model.account.caption, axis: .vertical)
                    Text(.mastodonCaptionHelp).font(.footnote).foregroundStyle(.secondary)
                    Toggle(isOn: $model.account.enabled) { Text(.mastodonAutomatic) }
                    Button(.settingsSave) { Task { await model.savePublishing() } }
                }
            }
            if let notice = model.notice { Section { Text(notice) } }
        }.navigationTitle(Text(.mastodonTitle))
    }
}

#if DEBUG
    #Preview { MastodonSettingsView.snapshotPreviews }
#endif

#if DEBUG
    extension MastodonSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "MastodonSettingsView",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                NavigationStack { MastodonSettingsView(model: DaylightModel.preview(
                    mode: .setup,
                    notice: nil,
                )) }.broadwayRoot()
            }
        }
    }
#endif
