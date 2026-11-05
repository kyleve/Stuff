import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct RecordingTimeZonePicker: View {
    @Bindable var model: RecordingTimeZonePickerModel
    @Binding var selection: TimeZone?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(model.zones, id: \.identifier) { zone in
            Button {
                selection = zone
                dismiss()
            } label: {
                HStack {
                    Text(WhereFormat.recordingTimeZone(zone))
                    Spacer()
                    if selection == zone {
                        Image(systemSymbol: .checkmark)
                            .accessibilityLabel(String(localized: .recordingCalendarSelectedZone))
                    }
                }
            }
            .accessibilityIdentifier("where_recording_zone_\(zone.identifier)")
        }
        .searchable(text: $model.search, prompt: String(localized: .recordingCalendarSearchZone))
        .overlay {
            if model.zones.isEmpty {
                ContentUnavailableView.search(text: model.search)
            }
        }
        .navigationTitle(String(localized: .recordingCalendarChooseZone))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
    extension RecordingTimeZonePicker: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let model: RecordingTimeZonePickerModel = {
                let model = RecordingTimeZonePickerModel()
                model.search = "New York"
                return model
            }()
            whereSnapshot(name: "Search", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    RecordingTimeZonePicker(model: model, selection: .constant(nil))
                }
            }
        }
    }

    #Preview { RecordingTimeZonePicker.snapshotPreviews }

    extension RecordingTimeZonePicker: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingTimeZonePicker.self,
            title: "Recording time zone",
        )
    }
#endif
