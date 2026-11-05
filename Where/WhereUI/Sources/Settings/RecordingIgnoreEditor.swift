import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Reviews the exact eligibility effect of an ignore edit without changing recording consent.
struct RecordingIgnoreEditor: View {
    let model: RecordingIgnoreEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.name)
                        .font(.headline)
                    switch model.draft {
                        case let .until(end):
                            RecordingIgnoreDateFields(end: end)
                        case let .restore(kind, _):
                            Text(kind == .resume ?
                                String(localized: .recordingIgnoreResumeDetail) :
                                String(localized: .recordingIgnoreUndoDetail))
                    }
                } footer: {
                    Text(String(localized: .recordingIgnoreDetail))
                }
                .disabled(model.controls.isBusy || model.controls.didApply)

                RecordingControlStatus(
                    model: model.controls,
                    context: .ignore,
                    canRetry: model.canRetry,
                    retry: { Task { await model.retry() } },
                )
                if let inspection = model.inspection {
                    switch inspection {
                        case let .success(inspection):
                            Section {
                                ForEach(inspection.changes, id: \.period) { change in
                                    VStack(alignment: .leading) {
                                        Text(WhereFormat.recordingPeriod(change.period))
                                            .font(.headline)
                                        Text(String(localized: .recordingIgnoreBefore(
                                            WhereFormat.recordingIgnoreOutcome(
                                                change.before,
                                                deviceID: model.deviceID,
                                            ),
                                        )))
                                        Text(String(localized: .recordingIgnoreAfter(
                                            WhereFormat.recordingIgnoreOutcome(
                                                change.after,
                                                deviceID: model.deviceID,
                                            ),
                                        )))
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            } header: {
                                Text(String(localized: .recordingIgnorePreview))
                            } footer: {
                                Text(String(localized: .recordingIgnorePrecedence))
                            }
                        case let .failure(error):
                            Section {
                                Label(
                                    WhereFormat.recordingIgnoreFailure(error),
                                    systemSymbol: .exclamationmarkTriangle,
                                )
                            }
                    }
                }
                if !model.controls.didApply {
                    Section {
                        switch model.edits {
                            case .success:
                                if model.canApply {
                                    Button(String(localized: .recordingIgnoreSave)) {
                                        Task { await model.apply() }
                                    }
                                    .accessibilityIdentifier("where_recording_ignore_apply")
                                } else if !model.canRetry {
                                    Button(String(localized: .recordingIgnoreReview)) {
                                        Task { await model.review() }
                                    }
                                    .accessibilityIdentifier("where_recording_ignore_review")
                                }
                            case let .failure(error):
                                Label(
                                    WhereFormat.recordingIgnoreFailure(error),
                                    systemSymbol: .exclamationmarkTriangle,
                                )
                        }
                    } footer: {
                        Text(String(localized: .recordingReviewSaveDetail))
                    }
                    .disabled(model.controls.isBusy)
                }
            }
            .environment(\.calendar, RecordingScopeEditorModel.pickerCalendar)
            .environment(\.timeZone, .gmt)
            .navigationTitle(String(localized: .recordingIgnoreTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: .commonDone)) { dismiss() }
                        .accessibilityIdentifier("where_recording_ignore_close")
                }
            }
        }
    }
}

private struct RecordingIgnoreDateFields: View {
    @Bindable var end: RecordingIgnoreEditorModel.EndDate

    var body: some View {
        WhereDatePicker(
            String(localized: .recordingIgnoreUntil),
            selection: $end.date,
            displayedComponents: .date,
        )
        .accessibilityIdentifier("where_recording_ignore_date")
        Text(WhereFormat.recordingTimeZone(end.timeZone))
            .foregroundStyle(.secondary)
        Text(String(localized: .recordingIgnoreEndDetail))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    extension RecordingIgnoreEditor: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in RecordingIgnorePreviewFixture.EditorScenario.allCases {
                let fixture = RecordingIgnorePreviewFixture(editor: scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .reviewed ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: fixture.prepare,
                ) { RecordingIgnorePreview(fixture: fixture) }
            }
        }
    }

    #Preview { RecordingIgnoreEditor.snapshotPreviews }

    extension RecordingIgnoreEditor: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingIgnoreEditor.self,
            title: "Review device ignore",
            navigationContainer: .none,
        )
    }
#endif
