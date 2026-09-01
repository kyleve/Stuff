import SnapshotKit
import SwiftUI
import ThrowCore

struct ProjectionIntensitySettingsView: View {
    private let session: ThrowSession
    @State private var intensityPercent: Double

    init(session: ThrowSession) {
        self.session = session
        _intensityPercent = State(initialValue: session.intensityPercent)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: .settingsIntensity)) {
                    Text(intensityPercent / 100, format: .percent)
                }
                Slider(value: $intensityPercent, in: 20 ... 100, step: 5)
                    .accessibilityLabel(Text(.settingsIntensity))
                    .accessibilityValue(
                        Text(intensityPercent / 100, format: .percent),
                    )
            } footer: {
                Text(.settingsProjectionIntensityDescription)
            }
        }
        .navigationTitle(Text(.settingsProjectionIntensity))
        .onChange(of: intensityPercent) { _, intensityPercent in
            do {
                let preferences = try session.globalPreferences
                    .replacingIntensityPercent(intensityPercent)
                session.updateGlobalPreferences(preferences)
            } catch is ThrowValidationError {
                return
            } catch {
                assertionFailure("Intensity validation produced an unexpected error: \(error)")
            }
        }
        .onChange(of: session.intensityPercent) { _, value in
            intensityPercent = value
        }
    }
}

#if DEBUG
    extension ProjectionIntensitySettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Default",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    ProjectionIntensitySettingsView(session: .fixture())
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview {
        ProjectionIntensitySettingsView.snapshotPreviews
    }
#endif
