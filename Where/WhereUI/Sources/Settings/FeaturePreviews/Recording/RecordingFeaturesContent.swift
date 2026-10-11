import SFSafeSymbols
import SwiftUI
import WhereCore

/// Builds gallery rows below the page's reveal and focus scopes so those scopes
/// store only this small view, rather than the complete concrete row tree.
struct RecordingFeaturesContent: View {
    let authorizationStatus: LocationAuthorizationStatus
    let isTracking: Bool

    var body: some View {
        FeatureGuidePanel(
            title: .settingsExploreRecordingAutomaticTitle,
            detail: .settingsExploreRecordingAutomaticDetail,
            symbol: .locationFill,
        ) {
            LocationStatusRow(status: authorizationStatus, isTracking: isTracking)
        }
        .featureMarketingRow(order: 1)
        .settingsRow(RecordingFeaturesView.Item.automatic, restingBackground: .clear)
        FeatureGuidePanel(
            title: .settingsExploreRecordingDevicesTitle,
            detail: .settingsExploreRecordingDevicesDetail,
            symbol: .iphoneAndArrowForward,
        ) {}
            .featureMarketingRow(order: 2)
            .settingsRow(RecordingFeaturesView.Item.devices, restingBackground: .clear)
        FeatureGuidePanel(
            title: .settingsExploreRecordingManualTitle,
            detail: .settingsExploreRecordingManualDetail,
            symbol: .calendarBadgePlus,
        ) {}
            .featureMarketingRow(order: 3)
            .settingsRow(RecordingFeaturesView.Item.manual, restingBackground: .clear)
        FeatureSettingsLink(destination: .devices).featureMarketingRow(order: 4)
        FeatureSettingsLink(destination: .loggedDays).featureMarketingRow(order: 5)
        FeatureSettingsLink(destination: .siri).featureMarketingRow(order: 6)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            RecordingFeaturesView(authorizationStatus: .always, isTracking: true, focus: nil)
        }
        .whereBroadwayRoot()
    }
#endif
