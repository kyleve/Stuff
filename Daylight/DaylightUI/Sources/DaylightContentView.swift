import DaylightCore
import DaylightMastodon
import SnapshotKit
import SwiftUI

public struct DaylightContentView: View {
    @Bindable var model: DaylightModel
    public init(model: DaylightModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.isArmed { UnattendedCaptureView(model: model) }
            else { NavigationStack { setup.navigationTitle(Text(.appTitle)) } }
        }
    }

    private var setup: some View {
        Form {
            Section {
                CameraSetupView(model: model)
                Button(.captureTest) { Task { await model.testShot() } }
                    .disabled(!model.ready || model.working)
            }
            Section {
                Button(.captureStart) { Task { await model.toggleArmed() } }
                    .disabled(!model.ready || model.working)
                Text(.captureInstructions).font(.footnote).foregroundStyle(.secondary)
                if let next = model.nextCapture { LabeledContent { Text(
                    next,
                    format: .dateTime.month().day().hour().minute(),
                ) } label: { Text(.captureNext) } }
            }
            if let notice = model.notice {
                Section {
                    Text(notice).foregroundStyle(.secondary)
                        .accessibilityLabel(Text(.statusNotice))
                }
            }
            Section {
                NavigationLink { ScheduleSettingsView(model: model) } label: { Text(.scheduleTitle)
                }
                NavigationLink { MastodonSettingsView(model: model) } label: { Text(.mastodonTitle)
                }
                NavigationLink { SequenceHistoryView(
                    sequences: model.recentHistory,
                    manualCaptures: model.manualHistory,
                ) } label: {
                    Text(.historyTitle)
                }
            }
        }
    }
}

#if DEBUG
    extension DaylightContentView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Setup",
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPhoneFullContent],
                    colorSchemes: [.light, .dark],
                ),
                settle: .immediate,
            ) {
                DaylightContentView(model: DaylightModel.preview(mode: .setup, notice: nil))
                    .broadwayRoot()
            }
            SnapshotCase(
                name: "Armed",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                DaylightContentView(model: DaylightModel.preview(mode: .armed, notice: nil))
                    .broadwayRoot()
            }
            SnapshotCase(
                name: "Interrupted",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                DaylightContentView(model: DaylightModel.preview(
                    mode: .suspended("Capture paused while the phone cools."),
                    notice: "A photo needs your attention in Photos.",
                )).broadwayRoot()
            }
            SnapshotCase(
                name: "Accessibility",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                DaylightContentView(model: DaylightModel.preview(mode: .setup, notice: nil))
                    .broadwayRoot()
                    .dynamicTypeSize(.accessibility3)
            }
        }
    }

    #Preview { DaylightContentView.snapshotPreviews }
#endif
