import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Confirms historical calendar context before the shared guarded save. The source-review
/// owner keeps this model alive until dismissal, including through failed save receipts.
struct RecordingCalendarEditor: View {
    @Bindable var model: RecordingCalendarEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        String(localized: .recordingScopeDayDevice),
                        selection: $model.deviceID,
                    ) {
                        Text(String(localized: .recordingScopeChooseDevice))
                            .tag(RecordingDeviceID?.none)
                        ForEach(model.devices, id: \.self) { deviceID in
                            Text(WhereFormat.recordingDevice(deviceID, names: model.names))
                                .fixedSize(horizontal: false, vertical: true)
                                .tag(Optional(deviceID))
                        }
                    }
                    .pickerStyle(.inline)
                    NavigationLink {
                        RecordingTimeZonePicker(model: model.zonePicker, selection: $model.timeZone)
                    } label: {
                        LabeledContent(String(localized: .recordingCalendarZone)) {
                            Text(model.timeZone.map(WhereFormat.recordingTimeZone) ??
                                String(localized: .recordingCalendarChooseZone))
                        }
                    }
                    .accessibilityIdentifier("where_recording_choose_zone")
                } footer: {
                    Text(String(localized: .recordingCalendarZoneDetail))
                }
                .disabled(model.controls.isBusy || model.controls.didApply)

                ForEach(model.periods) { selection in
                    RecordingCalendarPeriodFields(selection: selection)
                        .disabled(model.controls.isBusy || model.controls.didApply)
                }
                Section {
                    Text(String(localized: .recordingScopeUtcDetail))
                        .foregroundStyle(.secondary)
                }
                status
                if let recovery = model.reviewedRecovery {
                    Section {
                        ForEach(recovery.segments, id: \.self) { segment in
                            VStack(alignment: .leading) {
                                Text(WhereFormat.recordingCalendarPeriod(segment))
                                Text(WhereFormat.recordingPeriod(segment.period))
                                    .font(.caption)
                                Text(WhereFormat.recordingCalendarOffset(segment.context))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(String(localized: .recordingCalendarPreview))
                    } footer: {
                        Text(String(localized: .recordingCalendarPreserveDetail))
                    }
                }
                if !model.controls.didApply {
                    Section {
                        switch model.draft {
                            case .success:
                                if model.canApply {
                                    Button(String(localized: .recordingCalendarSave)) {
                                        Task { await model.apply() }
                                    }
                                    .accessibilityIdentifier("where_recording_calendar_apply")
                                } else if !model.canRetry {
                                    Button(String(localized: .recordingCalendarReview)) {
                                        Task { await model.review() }
                                    }
                                    .accessibilityIdentifier("where_recording_calendar_review")
                                }
                            case let .failure(error):
                                Label(
                                    WhereFormat.recordingCalendarFailure(error),
                                    systemSymbol: .exclamationmarkTriangle,
                                )
                        }
                    } footer: {
                        Text(String(localized: .recordingCalendarSaveDetail))
                    }
                    .disabled(model.controls.isBusy)
                }
            }
            .environment(\.calendar, RecordingScopeEditorModel.pickerCalendar)
            .environment(\.timeZone, .gmt)
            .navigationTitle(String(localized: .recordingCalendarTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: .commonDone)) { dismiss() }
                        .accessibilityIdentifier("where_recording_calendar_close")
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.controls.state {
            case .idle: EmptyView()
            case .reviewing:
                Section { ProgressView(String(localized: .recordingReviewLoading)) }
            case let .ready(review) where review.refreshed:
                Section {
                    Label(
                        String(localized: .recordingCalendarRefreshed),
                        systemSymbol: .arrowClockwise,
                    )
                    .accessibilityIdentifier("where_recording_calendar_refreshed")
                }
            case .ready: EmptyView()
            case .saving:
                Section { SavingStatusRow(text: String(localized: .manualSavingStatus)) }
            case .applied:
                Section {
                    Label(
                        String(localized: .recordingCalendarSaved),
                        systemSymbol: .checkmarkCircle,
                    )
                    .accessibilityIdentifier("where_recording_calendar_saved")
                }
            case let .failed(error, _):
                Section {
                    Label(
                        WhereFormat.recordingCalendarFailure(error),
                        systemSymbol: .exclamationmarkTriangle,
                    )
                    if model.canRetry {
                        Button(String(localized: .commonRetry)) { Task { await model.retry() } }
                            .accessibilityIdentifier("where_recording_calendar_retry")
                    }
                }
        }
    }
}

private struct RecordingCalendarPeriodFields: View {
    @Bindable var selection: RecordingCalendarEditorModel.PeriodSelection

    var body: some View {
        Section {
            Toggle(String(localized: .recordingCalendarIncludePeriod), isOn: $selection.isIncluded)
                .accessibilityLabel(String(localized: .recordingCalendarIncludeNamedPeriod(
                    WhereFormat.recordingInstant(selection.interval.start),
                    WhereFormat.recordingInstant(selection.interval.end),
                )))
            RecordingIntervalFields(interval: selection.interval)
                .disabled(!selection.isIncluded)
        } footer: {
            Text(String(localized: .recordingScopeExclusiveEnd))
        }
    }
}

#if DEBUG
    extension RecordingCalendarEditor: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in RecordingCalendarPreviewFixture.Scenario.allCases {
                let fixture = RecordingCalendarPreviewFixture(scenario: scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .reviewed ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: fixture.prepare,
                ) {
                    RecordingCalendarPreview(fixture: fixture)
                }
            }
        }
    }

    #Preview { RecordingCalendarEditor.snapshotPreviews }

    extension RecordingCalendarEditor: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingCalendarEditor.self,
            title: "Recording dates",
            navigationContainer: .none,
            routes: [.push(to: RecordingTimeZonePicker.flyoverID)],
        )
    }
#endif
