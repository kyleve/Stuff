import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Edits a proposed scope without writing history. Review returns a request to the source
/// screen; only that screen's newly prepared proposal can later be applied.
struct RecordingScopeEditor: View {
    @Bindable var model: RecordingScopeEditorModel
    let review: (RecordingChoiceRequest) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: .recordingScopeKind), selection: $model.kind) {
                        Text(String(localized: .recordingScopePeriods))
                            .tag(RecordingScopeEditorModel.Kind.periods)
                        Text(String(localized: .recordingScopeWholeDay))
                            .tag(RecordingScopeEditorModel.Kind.recordingDay)
                    }
                }
                switch model.draft {
                    case let .periods(intervals):
                        ForEach(intervals) { interval in
                            RecordingIntervalFields(interval: interval)
                        }
                        Section {
                            Text(String(localized: .recordingScopeUtcDetail))
                                .foregroundStyle(.secondary)
                        }
                    case let .recordingDay(day):
                        RecordingDayFields(
                            day: day,
                            names: model.names,
                            devices: model.devices,
                            action: model.action,
                        )
                }
                Section {
                    switch model.request {
                        case let .success(request):
                            Button(String(localized: .recordingScopeReview)) {
                                review(request)
                                dismiss()
                            }
                            .accessibilityIdentifier("where_recording_scope_review")
                        case let .failure(error):
                            Label(
                                WhereFormat.recordingScopeError(error),
                                systemSymbol: .exclamationmarkTriangle,
                            )
                    }
                } footer: {
                    Text(String(localized: .recordingScopePreviewDetail))
                }
            }
            .environment(\.calendar, RecordingScopeEditorModel.pickerCalendar)
            .environment(\.timeZone, .gmt)
            .navigationTitle(String(localized: .recordingScopeTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) { dismiss() }
                }
            }
        }
    }
}

private struct RecordingIntervalFields: View {
    @Bindable var interval: RecordingScopeEditorModel.Interval

    var body: some View {
        Section {
            WhereDatePicker(
                String(localized: .recordingScopeStart),
                selection: $interval.start,
                displayedComponents: [.date, .hourAndMinute],
            )
            WhereDatePicker(
                String(localized: .recordingScopeEnd),
                selection: $interval.end,
                displayedComponents: [.date, .hourAndMinute],
            )
        } footer: {
            Text(String(localized: .recordingScopeExclusiveEnd))
        }
    }
}

private struct RecordingDayFields: View {
    @Bindable var day: RecordingScopeEditorModel.Day
    let names: [RecordingDeviceID: String]
    let devices: [RecordingDeviceID]
    let action: HistoryDecision.Action

    var body: some View {
        Section {
            switch action {
                case let .select(deviceID):
                    LabeledContent(String(localized: .recordingScopeDayDevice)) {
                        Text(WhereFormat.recordingDevice(deviceID, names: names))
                    }
                case .automatic:
                    Picker(String(localized: .recordingScopeDayDevice), selection: $day.deviceID) {
                        Text(String(localized: .recordingScopeChooseDevice))
                            .tag(RecordingDeviceID?.none)
                        ForEach(
                            devices,
                            id: \.self,
                        ) { deviceID in
                            Text(WhereFormat.recordingDevice(deviceID, names: names))
                                .tag(Optional(deviceID))
                        }
                    }
            }
            WhereDatePicker(
                String(localized: .recordingScopeRecordedDate),
                selection: $day.date,
                displayedComponents: .date,
            )
            if day.needsDateConfirmation {
                Button(String(localized: .recordingScopeConfirmDate)) { day.confirmDate() }
            }
        } footer: {
            Text(String(localized: .recordingScopeDayDetail))
        }
    }
}

#if DEBUG
    extension RecordingScopeEditor: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for kind in [RecordingScopeEditorModel.Kind.periods, .recordingDay] {
                let fixture = RecordingReviewPreviewFixture(scenario: .selected)
                whereSnapshot(
                    name: kind == .periods ? "Periods" : "RecordingDay",
                    configurations: kind == .periods ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        .fullContentPhoneLightDark,
                    onReadyToMeasure: { await fixture.prepareScope(kind: kind) },
                    onReadyToSnapshot: { await fixture.prepareScope(kind: kind) },
                ) {
                    RecordingReviewPreview(fixture: fixture) { fixture in
                        if let editor = fixture.scopeEditor {
                            RecordingScopeEditor(model: editor, review: { _ in })
                                .id(editor.id)
                        }
                    }
                }
            }
        }
    }

    #Preview { RecordingScopeEditor.snapshotPreviews }

    extension RecordingScopeEditor: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingScopeEditor.self,
            title: "Recording scope",
            navigationContainer: .none,
        )
    }
#endif
