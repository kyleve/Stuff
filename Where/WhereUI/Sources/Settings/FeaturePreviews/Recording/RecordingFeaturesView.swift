import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A read-only walkthrough of recording & devices with explicit actions into existing screens.
struct RecordingFeaturesView: View {
    let authorizationStatus: LocationAuthorizationStatus
    let isTracking: Bool
    let focus: SettingsFocus?

    var body: some View {
        FeatureGuidePage(
            destination: .recording,
            tagline: .settingsExploreRecordingTagline,
            focus: focus,
        ) {
            RecordingFeaturesContent(
                authorizationStatus: authorizationStatus,
                isTracking: isTracking,
            )
        }
    }
}

extension RecordingFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .recording
    }

    enum Item: SettingsItem {
        case automatic
        case devices
        case manual

        var title: String {
            switch self {
                case .automatic: String(localized: .settingsExploreRecordingAutomaticTitle)
                case .devices: String(localized: .settingsExploreRecordingDevicesTitle)
                case .manual: String(localized: .settingsExploreRecordingManualTitle)
            }
        }

        var keywords: [String] {
            switch self {
                case .automatic: splitKeywords(
                        String(localized: .settingsExploreRecordingAutomaticKeywords),
                    )
                case .devices: splitKeywords(
                        String(localized: .settingsExploreRecordingDevicesKeywords),
                    )
                case .manual: splitKeywords(
                        String(localized: .settingsExploreRecordingManualKeywords),
                    )
            }
        }
    }
}

#if DEBUG
    extension RecordingFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Recording",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
            ) {
                RecordingFeaturesView(authorizationStatus: .always, isTracking: true, focus: nil)
            }
            whereSnapshot(
                name: "Denied",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                RecordingFeaturesView(authorizationStatus: .denied, isTracking: false, focus: nil)
            }
            whereSnapshot(
                name: "Paused",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                RecordingFeaturesView(authorizationStatus: .always, isTracking: false, focus: nil)
            }
        }
    }

    #Preview {
        NavigationStack { RecordingFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }

    extension RecordingFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingFeaturesView.self,
            title: "Recording & Devices",
            routes: [
                .push(to: DevicesSettingsView.flyoverID),
                .push(to: LoggedDaysView.flyoverID),
                .push(to: SiriFeaturesView.flyoverID),
            ],
        )
    }
#endif
