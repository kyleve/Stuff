import SnapshotKit
import SwiftUI
import WhereCore

/// An explicit interval into the shared source review, including automatic choices that
/// raised no issue. The open review retains its scope until it is dismissed.
struct RecordingHistoryView: View {
    @State private var model: RecordingHistoryModel

    init(session: WhereSession) {
        _model = State(initialValue: .init(services: session.services, now: session.now))
    }

    init(model: RecordingHistoryModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                WhereDatePicker(
                    String(localized: .recordingScopeStart),
                    selection: $model.start,
                    displayedComponents: [.date, .hourAndMinute],
                )
                WhereDatePicker(
                    String(localized: .recordingScopeEnd),
                    selection: $model.end,
                    displayedComponents: [.date, .hourAndMinute],
                )
            } footer: {
                Text(String(localized: .recordingHistoryRangeDetail))
            }
            Section {
                if case let .failure(error) = model.period {
                    Text(WhereFormat.recordingScopeError(error))
                }
                Button(String(localized: .recordingHistoryInspect)) { model.inspect() }
                    .disabled(!model.canInspect)
                    .accessibilityIdentifier("where_recording_history_inspect")
            } footer: { Text(String(localized: .recordingHistoryDetail)) }
        }
        .environment(\.calendar, RecordingScopeEditorModel.pickerCalendar)
        .environment(\.timeZone, .gmt)
        .navigationTitle(String(localized: .recordingHistoryTitle))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $model.inspection) { inspection in
            NavigationStack {
                RecordingChoiceView(model: inspection.model, completion: .save)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: .commonDone)) { model.inspection = nil }
                                .accessibilityIdentifier("where_recording_history_close")
                        }
                    }
            }
        }
        .alert(
            String(localized: .recordingHistoryErrorTitle),
            isPresented: $model.isShowingError,
            presenting: model.error,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { _ in Text(String(localized: .recordingReviewLoadFailed)) }
    }
}

extension RecordingHistoryView: SettingsSection {
    static var destination: SettingsDestination {
        .recordingHistory
    }

    enum Item: SettingsItem {
        case history
        var title: String {
            String(localized: .recordingHistoryTitle)
        }

        var keywords: [String] {
            splitKeywords(String(localized: .recordingHistorySearchKeywords))
        }
    }
}

#if DEBUG
    extension RecordingHistoryView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let fixture = RecordingHistoryPreviewFixture()
            whereSnapshot(
                name: "Range",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations,
                onReadyToMeasure: fixture.prepare,
            ) {
                RecordingHistoryPreview(fixture: fixture)
            }
        }
    }

    #Preview { RecordingHistoryView.snapshotPreviews }
    extension RecordingHistoryView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingHistoryView.self,
            title: "Recording history",
            navigationContainer: .none,
            routes: [.modal(to: RecordingChoiceView.flyoverID)],
        )
    }
#endif
