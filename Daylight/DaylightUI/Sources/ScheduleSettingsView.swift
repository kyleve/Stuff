import BroadwayUI
import SnapshotKit
import SwiftUI

struct ScheduleSettingsView: View {
    @Bindable var model: DaylightModel
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text(.siteLatitude).font(.caption).foregroundStyle(.secondary)
                    TextField(.siteLatitude, value: $model.settings.site.latitude, format: .number)
                }
                VStack(alignment: .leading) {
                    Text(.siteLongitude).font(.caption).foregroundStyle(.secondary)
                    TextField(
                        .siteLongitude,
                        value: $model.settings.site.longitude,
                        format: .number,
                    )
                }
                VStack(alignment: .leading) {
                    Text(.siteTimeZone).font(.caption).foregroundStyle(.secondary)
                    TextField(.siteTimeZone, text: $model.settings.site.timeZoneIdentifier)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            } header: { Text(.siteTitle) }
            Section {
                Stepper(value: $model.settings.sunrise.minutesBefore, in: 0 ... 180) {
                    Text(.scheduleBefore(model.settings.sunrise.minutesBefore))
                }
                Stepper(value: $model.settings.sunrise.minutesAfter, in: 0 ... 180) {
                    Text(.scheduleAfter(model.settings.sunrise.minutesAfter))
                }
                Stepper(value: $model.settings.sunrise.intervalMinutes, in: 1 ... 60) {
                    Text(.scheduleInterval(model.settings.sunrise.intervalMinutes))
                }
            } header: { Text(.eventSunrise) }
            Section {
                Stepper(value: $model.settings.sunset.minutesBefore, in: 0 ... 180) {
                    Text(.scheduleBefore(model.settings.sunset.minutesBefore))
                }
                Stepper(value: $model.settings.sunset.minutesAfter, in: 0 ... 180) {
                    Text(.scheduleAfter(model.settings.sunset.minutesAfter))
                }
                Stepper(value: $model.settings.sunset.intervalMinutes, in: 1 ... 60) {
                    Text(.scheduleInterval(model.settings.sunset.intervalMinutes))
                }
            } header: { Text(.eventSunset) }
            Section {
                Button(.settingsSave) { Task { await model.saveSettings() } }
                Text(.scheduleFrozen).font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle(Text(.scheduleTitle))
    }
}

#if DEBUG
    #Preview { ScheduleSettingsView.snapshotPreviews }
#endif

#if DEBUG
    extension ScheduleSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "ScheduleSettingsView",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                NavigationStack { ScheduleSettingsView(model: DaylightModel.preview(
                    mode: .setup,
                    notice: nil,
                )) }.broadwayRoot()
            }
        }
    }
#endif
